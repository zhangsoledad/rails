require 'abstract_unit'
require 'fileutils'
require 'action_view/dependency_tracker'

class FixtureTemplate
  attr_reader :source, :handler

  def initialize(template_path)
    @source = File.read(template_path)
    @handler = ActionView::Template.handler_for_extension(:erb)
  rescue Errno::ENOENT
    raise ActionView::MissingTemplate.new([], "", [], true, [])
  end
end

class FixtureFinder < ActionView::LookupContext
  FIXTURES_DIR = "#{File.dirname(__FILE__)}/../fixtures/digestor"

  def initialize(details = {})
    super(ActionView::PathSet.new(['digestor']), details, [])
  end
end

class TemplateDigestorTest < ActionView::TestCase
  def setup
    @cwd     = Dir.pwd
    @tmp_dir = Dir.mktmpdir

    FileUtils.cp_r FixtureFinder::FIXTURES_DIR, @tmp_dir
    Dir.chdir @tmp_dir
  end

  def teardown
    Dir.chdir @cwd
    FileUtils.rm_r @tmp_dir
    ActionView::Digestor.cache.clear
  end

  def test_top_level_change_reflected
    assert_digest_difference("messages/show") do
      change_template("messages/show")
    end
  end

  def test_explicit_dependency
    assert_digest_difference("messages/show") do
      change_template("messages/_message")
    end
  end

  def test_explicit_dependency_in_multiline_erb_tag
    assert_digest_difference("messages/show") do
      change_template("messages/_form")
    end
  end

  def test_explicit_dependency_wildcard
    assert_digest_difference("events/index") do
      change_template("events/_completed")
    end
  end

  def test_explicit_dependency_wildcard_picks_up_added_file
    old_caching, ActionView::Resolver.caching = ActionView::Resolver.caching, false

    assert_digest_difference("events/index") do
      add_template("events/_uncompleted")
    end
  ensure
    remove_template("events/_uncompleted")
    ActionView::Resolver.caching = old_caching
  end

  def test_explicit_dependency_wildcard_picks_up_removed_file
    old_caching, ActionView::Resolver.caching = ActionView::Resolver.caching, false
    add_template("events/_subscribers_changed")

    assert_digest_difference("events/index") do
      remove_template("events/_subscribers_changed")
    end
  ensure
    ActionView::Resolver.caching = old_caching
  end

  def test_second_level_dependency
    assert_digest_difference("messages/show") do
      change_template("comments/_comments")
    end
  end

  def test_second_level_dependency_within_same_directory
    assert_digest_difference("messages/show") do
      change_template("messages/_header")
    end
  end

  def test_third_level_dependency
    assert_digest_difference("messages/show") do
      change_template("comments/_comment")
    end
  end

  def test_directory_depth_dependency
    assert_digest_difference("level/below/index") do
      change_template("level/below/_header")
    end
  end

  def test_logging_of_missing_template
    assert_logged "Couldn't find template for digesting: messages/something_missing" do
      digest("messages/show")
    end
  end

  def test_logging_of_missing_template_ending_with_number
    assert_logged "Couldn't find template for digesting: messages/something_missing_1" do
      digest("messages/show")
    end
  end

  def test_logging_of_missing_template_for_dependencies
    assert_logged "'messages/something_missing' file doesn't exist, so no dependencies" do
      dependencies("messages/something_missing")
    end
  end

  def test_logging_of_missing_template_for_nested_dependencies
    assert_logged "'messages/something_missing' file doesn't exist, so no dependencies" do
      nested_dependencies("messages/something_missing")
    end
  end

  def test_nested_template_directory
    assert_digest_difference("messages/show") do
      change_template("messages/actions/_move")
    end
  end

  def test_recursion_in_renders
    assert digest("level/recursion") # assert recursion is possible
    assert_not_nil digest("level/recursion") # assert digest is stored
  end

  def test_chaining_the_top_template_on_recursion
    assert digest("level/recursion") # assert recursion is possible

    assert_digest_difference("level/recursion") do
      change_template("level/recursion")
    end

    assert_not_nil digest("level/recursion") # assert digest is stored
  end

  def test_chaining_the_partial_template_on_recursion
    assert digest("level/recursion") # assert recursion is possible

    assert_digest_difference("level/recursion") do
      change_template("level/_recursion")
    end

    assert_not_nil digest("level/recursion") # assert digest is stored
  end

  def test_dont_generate_a_digest_for_missing_templates
    assert_equal '', digest("nothing/there")
  end

  def test_collection_dependency
    assert_digest_difference("messages/index") do
      change_template("messages/_message")
    end

    assert_digest_difference("messages/index") do
      change_template("events/_event")
    end
  end

  def test_collection_derived_from_record_dependency
    assert_digest_difference("messages/show") do
      change_template("events/_event")
    end
  end

  def test_details_are_included_in_cache_key
    # Cache the template digest.
    @finder = FixtureFinder.new({:formats => [:html]})
    old_digest = digest("events/_event")

    # Change the template; the cached digest remains unchanged.
    change_template("events/_event")

    # The details are changed, so a new cache key is generated.
    @finder = FixtureFinder.new

    # The cache is busted.
    assert_not_equal old_digest, digest("events/_event")
  end

  def test_extra_whitespace_in_render_partial
    assert_digest_difference("messages/edit") do
      change_template("messages/_form")
    end
  end

  def test_extra_whitespace_in_render_named_partial
    assert_digest_difference("messages/edit") do
      change_template("messages/_header")
    end
  end

  def test_extra_whitespace_in_render_record
    assert_digest_difference("messages/edit") do
      change_template("messages/_message")
    end
  end

  def test_extra_whitespace_in_render_with_parenthesis
    assert_digest_difference("messages/edit") do
      change_template("events/_event")
    end
  end

  def test_old_style_hash_in_render_invocation
    assert_digest_difference("messages/edit") do
      change_template("comments/_comment")
    end
  end

  def test_variants
    assert_digest_difference("messages/new", variants: [:iphone]) do
      change_template("messages/new",     :iphone)
      change_template("messages/_header", :iphone)
    end
  end

  def test_dependencies_via_options_results_in_different_digest
    digest_plain        = digest("comments/_comment")
    digest_fridge       = digest("comments/_comment", dependencies: ["fridge"])
    digest_phone        = digest("comments/_comment", dependencies: ["phone"])
    digest_fridge_phone = digest("comments/_comment", dependencies: ["fridge", "phone"])

    assert_not_equal digest_plain, digest_fridge
    assert_not_equal digest_plain, digest_phone
    assert_not_equal digest_plain, digest_fridge_phone
    assert_not_equal digest_fridge, digest_phone
    assert_not_equal digest_fridge, digest_fridge_phone
    assert_not_equal digest_phone, digest_fridge_phone
  end

  def test_digest_cache_cleanup_with_recursion
    first_digest = digest("level/_recursion")
    second_digest = digest("level/_recursion")

    assert first_digest

    # If the cache is cleaned up correctly, subsequent digests should return the same
    assert_equal first_digest, second_digest
  end

  def test_digest_cache_cleanup_with_recursion_and_template_caching_off
    resolver_before = ActionView::Resolver.caching
    ActionView::Resolver.caching = false

    first_digest = digest("level/_recursion")
    second_digest = digest("level/_recursion")

    assert first_digest

    # If the cache is cleaned up correctly, subsequent digests should return the same
    assert_equal first_digest, second_digest
  ensure
    ActionView::Resolver.caching = resolver_before
  end


  private
    def assert_logged(message)
      old_logger = ActionView::Base.logger
      log = StringIO.new
      ActionView::Base.logger = Logger.new(log)

      begin
        yield

        log.rewind
        assert_match message, log.read
      ensure
        ActionView::Base.logger = old_logger
      end
    end

    def assert_digest_difference(template_name, options = {})
      previous_digest = digest(template_name, options)
      ActionView::Digestor.cache.clear

      yield

      assert_not_equal previous_digest, digest(template_name, options), "digest didn't change"
      ActionView::Digestor.cache.clear
    end

    def digest(template_name, options = {})
      options = options.dup

      finder.variants = options.delete(:variants) || []

      ActionView::Digestor.digest({ name: template_name, finder: finder }.merge(options))
    end

    def dependencies(template_name)
      ActionView::Digestor.new(template_name, finder).dependencies
    end

    def nested_dependencies(template_name)
      ActionView::Digestor.new(template_name, finder).nested_dependencies
    end

    def finder
      @finder ||= FixtureFinder.new
    end

    def change_template(template_name, variant = nil)
      variant = "+#{variant}" if variant.present?

      File.open("digestor/#{template_name}.html#{variant}.erb", "w") do |f|
        f.write "\nTHIS WAS CHANGED!"
      end
    end
    alias_method :add_template, :change_template

    def remove_template(template_name)
      File.delete("digestor/#{template_name}.html.erb")
    end
end
