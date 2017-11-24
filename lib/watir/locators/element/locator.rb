module Watir
  module Locators
    class Element
      class Locator
        attr_reader :selector_builder
        attr_reader :element_validator

        WD_FINDERS = [
          :class,
          :class_name,
          :css,
          :id,
          :link,
          :link_text,
          :name,
          :partial_link_text,
          :tag_name,
          :xpath
        ]

        # Regular expressions that can be reliably converted to xpath `contains`
        # expressions in order to optimize the locator.
        CONVERTABLE_REGEXP = %r{
          \A
            ([^\[\]\\^$.|?*+()]*) # leading literal characters
            [^|]*?                # do not try to convert expressions with alternates
            ([^\[\]\\^$.|?*+()]*) # trailing literal characters
          \z
        }x

        def initialize(query_scope, selector, selector_builder, element_validator)
          @query_scope = query_scope # either element or browser
          @selector = selector.dup
          @selector_builder = selector_builder
          @element_validator = element_validator
        end

        def locate
          using_selenium(:first) || using_watir(:first)
        rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::StaleElementReferenceError
          nil
        end

        def locate_all
          return [@selector[:element]] if @selector.key?(:element)
          using_selenium(:all) || using_watir(:all)
        end

        private

        def using_selenium(filter = :first)
          selector = @selector.dup
          tag_name = selector[:tag_name].is_a?(::Symbol) ? selector[:tag_name].to_s : selector[:tag_name]
          selector.delete(:tag_name) if selector.size > 1

          WD_FINDERS.each do |sel|
            next unless (value = selector.delete(sel))
            return unless selector.empty? && wd_supported?(sel, value)
            if filter == :all
              found = locate_elements(sel, value)
              return found if sel == :tag_name
              return filter_elements(found, {tag_name: tag_name}, filter: filter).compact
            else
              found = locate_element(sel, value)
              return sel != :tag_name && tag_name && !validate([found], tag_name) ? nil : found
            end
          end
          nil
        end

        def using_watir(filter = :first)
          selector = selector_builder.normalized_selector
          tag_name = selector[:tag_name].is_a?(::Symbol) ? selector[:tag_name].to_s : selector[:tag_name]
          validation_required = (selector.key?(:css) || selector.key?(:xpath)) && tag_name

          if selector.key?(:index) && filter == :all
            raise ArgumentError, "can't locate all elements by :index"
          end
          idx = selector.delete(:index) unless selector[:adjacent]

          filter_selector = delete_filters_from(selector)
# TODO: make sure we are not doing unnecessary tag_name filtering
          filter_selector[:tag_name] = tag_name if tag_name

          query_scope = ensure_scope_context

          if filter_selector.key?(:label) && selector_builder.should_use_label_element?
            label = label_from_text(filter_selector.delete(:label)) || return
            if (id = label.attribute('for'))
              selector[:id] = id
            else
              query_scope = label
            end
          end

          how, what = selector_builder.build(selector)
          unless how
            raise Error, "internal error: unable to build Selenium selector from #{selector.inspect}"
          end

          if how == :xpath && can_convert_regexp_to_contains?
            filter_selector.each do |key, value|
              next if key == :tag_name || key == :text

              predicates = regexp_selector_to_predicates(key, value)
              what = "(#{what})[#{predicates.join(' and ')}]" unless predicates.empty?
              filter_selector.delete(key)
            end
          end



          needs_filtering = idx && idx != 0 || validation_required || filter == :all || !filter_selector.empty?

          return locate_element(how, what, query_scope) unless needs_filtering

          elements = locate_elements(how, what, query_scope) || []
          filter_elements(elements, filter_selector, idx: idx, filter: filter)
        end

        def validate(elements, tag_name)
          elements.compact.all? { |element| element_validator.validate(element, {tag_name: tag_name}) }
        end

        def fetch_value(element, how)
          case how
          when :text
            vis = element.text
            all = Watir::Element.new(@query_scope, element: element).send(:execute_js, :getTextContent, element).strip
            unless all == vis.strip
              Watir.logger.deprecate(':text locator with RegExp values to find elements based on only visible text', ":visible_text")
            end
            vis
          when :visible
            element.displayed?
          when :visible_text
            element.text
          when :tag_name
            element.tag_name.downcase
          when :href
            (href = element.attribute(:href)) && href.strip
          else
            element.attribute(how.to_s.tr("_", "-").to_sym)
          end
        end

        def filter_elements(elements, selector, idx: nil, filter: :first)
# TODO: when filter: :first, stop filtering when idx found
          matches = elements.select { |el| matches_selector?(el, selector) }
          filter == :first ? matches[idx || 0] : matches
        end

        def delete_filters_from(selector)
          filter_selector = {}

          [:visible, :visible_text].each do |how|
            next unless selector.key?(how)
            filter_selector[how] = selector.delete(how)
          end

          selector.dup.each do |how, what|
            next unless what.is_a?(Regexp)
            filter_selector[how] = selector.delete(how)
          end

          filter_selector
        end

        def label_from_text(label_exp)
          # TODO: this won't work correctly if @wd is a sub-element
          locate_elements(:tag_name, 'label').find do |el|
            matches_selector?(el, text: label_exp)
          end
        end

        def matches_selector?(element, selector)
          selector.all? do |how, what|
            if how == :tag_name && what.is_a?(String)
              element_validator.validate(element, {tag_name: what})
            else
              what === fetch_value(element, how)
            end
          end
        end

        def can_convert_regexp_to_contains?
          true
        end

        def regexp_selector_to_predicates(key, re)
          return [] if re.casefold?

          match = re.source.match(CONVERTABLE_REGEXP)
          return [] unless match

          lhs = selector_builder.xpath_builder.lhs_for(nil, key)
          match.captures.reject(&:empty?).map do |literals|
            "contains(#{lhs}, #{XpathSupport.escape(literals)})"
          end
        end

        def ensure_scope_context
          @query_scope.wd
        end

        def locate_element(how, what, scope = @query_scope.wd)
          scope.find_element(how, what)
        end

        def locate_elements(how, what, scope = @query_scope.wd)
          scope.find_elements(how, what)
        end

        def wd_supported?(how, what)
          return false unless what.kind_of?(String)
          return false if [:class, :class_name].include?(how) && what.include?(' ')
          %i[partial_link_text link_text link].each do |loc|
            next unless how == loc
            Watir.logger.deprecate(":#{loc} locator", ':visible_text')
          end
          true
        end
      end
    end
  end
end
