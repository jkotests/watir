require "watirspec_helper"

describe "ShadowRoot" do
  before :each do
    browser.goto(WatirSpec.url_for("shadow_dom.html"))
  end

  compliant_on :chrome do
    describe "#element" do
      it "finds elements by :css" do
        expect(browser.p(id: "hostElement").shadow_root.element(css: "#last")).to exist
      end

      it "finds elements by :id" do
        expect(browser.p(id: "hostElement").shadow_root.span(id: "last")).to exist
      end
    end

    describe "#elements" do
      it "finds a collection of elements" do
        expect(browser.p(id: "hostElement").shadow_root.elements(css: "span").count).to eq(3)
      end
    end
  end
end
