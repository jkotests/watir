require "selenium-webdriver"
require "json"

require "watir/exceptions"
require "watir/container"
require "watir/element_locator"
require "watir/xpath_builder"
require "watir/browser"

require "watir/base_element"
require "watir/elements/generated"

require "watir/elements/button"
require "watir/elements/checkbox"
require "watir/elements/file_field"
require "watir/elements/headings"
require "watir/elements/hidden"
require "watir/elements/link"
require "watir/elements/radio"
require "watir/elements/text_field"

module Watir
  include Selenium
end
