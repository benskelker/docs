# frozen_string_literal: true

module AlternativeLanguageLookup
  ##
  # Load alternative examples in alternative languages. Creating this class is
  # comparatively heavy because it parses the example. It'll also log warnings
  # if there are problems with the example. So only create it if you plan to
  # use the example.
  class Alternative
    include Asciidoctor::Logging

    LAYOUT_DESCRIPTION = <<~LOG
      Alternative language must be a code block followed optionally by a callout list
    LOG

    def initialize(document, lang, path)
      @document = document
      @lang = lang
      @path = path
      @counter = @document.attr 'alternative_language_counter', 0
      @text = nil
      load
      return unless validate

      munge
      @document.attributes['alternative_language_counter'] = @counter + 1
      @text = @child.convert
    end

    ##
    # A block that can be inserted into the main document if we've successfully
    # loaded, validated, and munged the alternative. nil otherwise.
    def block(parent)
      return unless @text

      Asciidoctor::Block.new parent, :pass, source: @text
    end

    def load
      # Parse the included portion as asciidoc but not as a "child" document
      # because that is for parsing text we've already parsed once. This is
      # text that we're detecting very late in the process.
      @child = Asciidoctor::Document.new(
        "include::#{@path}[]",
        attributes: @document.attributes.dup,
        safe: @document.safe,
        backend: @document.backend,
        doctype: Asciidoctor::DEFAULT_DOCTYPE,
        sourcemap: @document.sourcemap,
        base_dir: @document.base_dir,
        to_dir: @document.options[:to_dir]
      )
      @child.parse
    end

    def validate
      unless @child.blocks.length == 1 || @child.blocks.length == 2
        log_warn @child.source_location, <<~LOG.strip
          #{LAYOUT_DESCRIPTION} but was:
          #{@child.blocks}
        LOG
        return false
      end

      @listing = @child.blocks[0]
      @colist = @child.blocks[1]
      check_listing & check_colist
    end

    ##
    # Return false if the block in listing position isn't a listing or is
    # otherwise invalid. Otherwise returns true.
    def check_listing
      unless @listing.context == :listing
        log_warn @listing.source_location, <<~LOG.strip
          #{LAYOUT_DESCRIPTION} but the first block was a #{@listing.context}.
        LOG
        return false
      end
      unless (listing_lang = @listing.attr 'language') == @lang
        log_warn @listing.source_location, <<~LOG.strip
          Alternative language listing must have lang=#{@lang} but was #{listing_lang}.
        LOG
        return false
      end

      true
    end

    ##
    # Return false if block in the colist position isn't a colist.
    # Otherwise returns true.
    def check_colist
      return true unless @colist

      unless @colist.context == :colist
        log_warn @colist.source_location, <<~LOG.strip
          #{LAYOUT_DESCRIPTION} but the second block was a #{@colist.context}.
        LOG
        return false
      end
      true
    end

    ##
    # Warn that there is some problem with this alternative.
    def log_warn(location, message)
      logger.warn message_with_context message, source_location: location
    end

    ##
    # Munge the loaded document into something we can include in the
    # main document.
    def munge
      @listing.attributes['role'] = 'alternative'
      # Munge the callouts so they don't collide with the parent doc
      @listing.document.callouts.current_list.each do |co|
        co[:id] = munge_coid co[:id]
      end
      return unless @colist

      @colist.attributes['role'] = "alternative lang-#{@lang}"
      munge_list_coids
    end

    ##
    # Munge the link targets so they link properly to the munged ids in the
    # alternate example
    def munge_list_coids
      @colist.items.each do |item|
        coids = item.attr 'coids'
        next unless coids

        newcoids = []
        coids.split(' ').each do |coid|
          newcoids << munge_coid(coid)
        end
        item.attributes['coids'] = newcoids.join ' '
      end
    end

    def munge_coid(coid)
      "A#{@counter}-#{coid}"
    end
  end
end
