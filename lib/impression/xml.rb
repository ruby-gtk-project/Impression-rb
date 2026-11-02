# frozen_string_literal: true

require "strscan"

module Impression
  # Xml is the element tree the osinfo-db parser walks.
  #
  # Upstream parses osinfo-db's XML with roxmltree (src/online.rs). Ruby's own
  # REXML is a bundled gem and is not in this app's runtime closure, so the
  # shapes src/online.rs asks of a document — find a descendant by tag, read a
  # child's text, read an attribute, iterate same-named children — are answered
  # by this reader instead of pulling a parser into the closure.
  module Xml
    ENTITIES = {
      "lt"   => "<",
      "gt"   => ">",
      "amp"  => "&",
      "quot" => '"',
      "apos" => "'",
    }.freeze

    NAME = /[\w:.-]+/

    # Node is one element: its name, its attributes, its child elements and the
    # text directly inside it.
    class Node
      attr_reader :name, :attributes, :children
      attr_accessor :text

      def initialize(name, attributes)
        @name = name
        @attributes = attributes
        @children = []
        @text = nil
      end

      def [](attribute) = attributes[attribute]

      def child(tag) = children.find { |node| node.name == tag }

      def child_text(tag) = child(tag)&.text

      def each_child(tag) = children.select { |node| node.name == tag }

      # The first element with this tag anywhere below (or at) this node, which
      # is what roxmltree's descendants().find(has_tag_name) does.
      def descendant(tag)
        case name
        when tag
          self
        else
          children.filter_map { |node| node.descendant(tag) }.first
        end
      end
    end

    def self.parse(source)
      scanner = StringScanner.new(source)
      skip_noise(scanner)
      element(scanner)
    end

    # Declarations, comments and doctypes, in any order, before the root.
    def self.skip_noise(scanner)
      loop do
        scanner.skip(/\s+/)
        skipped = scanner.skip(/<\?.*?\?>/m) ||
          scanner.skip(/<!--.*?-->/m) ||
          scanner.skip(/<!DOCTYPE[^>]*>/m)
        case skipped
        when nil
          break
        end
      end
    end

    def self.element(scanner)
      case scanner.scan(/<(#{NAME})/o)
      when nil
        nil
      else
        open_element(scanner, scanner[1])
      end
    end

    def self.open_element(scanner, name)
      Node.new(name, attributes(scanner)).tap do |node|
        case scanner.skip(%r{\s*/>})
        when nil
          scanner.skip(/\s*>/)
          content(scanner, node)
        end
      end
    end

    def self.attributes(scanner)
      {}.tap do |found|
        loop do
          case scanner.scan(/\s*(#{NAME})\s*=\s*"([^"]*)"|\s*(#{NAME})\s*=\s*'([^']*)'/o)
          when nil
            break
          else
            found[scanner[1] || scanner[3]] = unescape(scanner[2] || scanner[4])
          end
        end
      end
    end

    def self.content(scanner, node)
      text = +""
      loop do
        text << unescape(scanner.scan(/[^<]+/).to_s)
        case
        when scanner.eos?
          break
        when scanner.skip(%r{</#{NAME}\s*>}o)
          break
        when scanner.skip(/<!--.*?-->/m)
          next
        when scanner.skip(/<\?.*?\?>/m)
          next
        else
          cdata_or_child(scanner, node, text)
        end
      end
      node.text = text.strip
    end

    def self.cdata_or_child(scanner, node, text)
      case scanner.scan(/<!\[CDATA\[(.*?)\]\]>/m)
      when nil
        child_element(scanner, node)
      else
        text << scanner[1]
      end
    end

    # A malformed tag would otherwise spin the content loop forever, so a
    # position that did not move consumes one character.
    def self.child_element(scanner, node)
      before = scanner.pos
      child = element(scanner)
      case child
      when nil
        scanner.pos = before + 1
      else
        node.children << child
      end
    end

    def self.unescape(text)
      text.gsub(/&(#x?\h+|\w+);/) { entity_value(Regexp.last_match(1)) }
    end

    def self.entity_value(entity)
      case entity
      when /\A#x(\h+)\z/
        Regexp.last_match(1).to_i(16).chr("UTF-8")
      when /\A#(\d+)\z/
        Regexp.last_match(1).to_i.chr("UTF-8")
      else
        ENTITIES.fetch(entity, "&#{entity};")
      end
    end
  end
end
