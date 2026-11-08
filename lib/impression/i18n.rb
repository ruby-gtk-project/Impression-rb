# frozen_string_literal: true

require "fiddle"

module Impression
  # I18n looks a string up in the translation catalogue.
  #
  # Ported from upstream's po/ and the gettext calls its blueprint and Rust
  # sources make: upstream's strings are marked with gettext/_() and meson
  # compiles po/*.po into the .mo catalogues the C library then reads.
  #
  # The catalogues are the same ones, compiled by `rake locale` for a run out
  # of the repository and by the flake's install phase for a packaged one. The
  # lookup itself goes to glibc's own gettext through Fiddle rather than to the
  # gettext gem, which would put a second runtime gem (and a C extension) in
  # the app's closure for three calls.
  module I18n
    DOMAIN = "impression"

    # glibc's locale.h: LC_ALL.
    LC_ALL = 6

    # Where a compiled catalogue may live: an explicit override first, then the
    # tree `rake locale` writes, then every XDG data directory — which is how
    # the packaged app's own share/locale is found, since the wrapper puts its
    # prefix on XDG_DATA_DIRS.
    def self.candidates
      [
        ENV.fetch("IMPRESSION_LOCALE_DIR", nil),
        File.expand_path("../../tmp/locale", __dir__),
        *ENV.fetch("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
          .split(File::PATH_SEPARATOR)
          .map { |directory| File.join(directory, "locale") },
      ].compact
    end

    # Lib binds the four libc calls a gettext-using program makes at startup
    # plus the lookup itself. glibc carries gettext in libc, so no separate
    # libintl is needed.
    module Lib
      SIGNATURES = {
        setlocale:               [[Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        bindtextdomain:          [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        bind_textdomain_codeset: [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        textdomain:              [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        gettext:                 [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
      }.freeze

      def self.handle = @handle ||= Fiddle.dlopen("libc.so.6")

      def self.functions = @functions ||= {}

      def self.function(name)
        functions[name] ||= SIGNATURES.fetch(name).then do |arguments, result|
          Fiddle::Function.new(handle[name.to_s], arguments, result)
        end
      end

      SIGNATURES.each_key do |name|
        define_singleton_method(name) { |*values| function(name).call(*values) }
      end
    end

    # The first candidate that actually holds a catalogue for this domain, so a
    # half-installed directory earlier in the list cannot shadow a real one.
    def self.locale_dir
      candidates.find { |directory| !Dir.glob(catalogue_glob(directory)).empty? }
    end

    def self.catalogue_glob(directory)
      File.join(
        directory,
        "*/LC_MESSAGES",
        "#{DOMAIN}.mo",
      )
    end

    # Binds the domain once, at the first lookup: the locale comes from the
    # environment, and the catalogue is read as UTF-8 whatever the locale's own
    # codeset is, because that is what GTK is handed.
    def self.setup
      @setup ||= begin
        Lib.setlocale(LC_ALL, "")
        locale_dir.then do |directory|
          case directory
          when nil
            nil
          else
            Lib.bindtextdomain(DOMAIN, directory)
          end
        end
        Lib.bind_textdomain_codeset(DOMAIN, "UTF-8")
        Lib.textdomain(DOMAIN)
        true
      end
    end

    # The translation of text, or text itself when the catalogue has none.
    def self.translate(text)
      setup
      Lib.gettext(text.to_s).to_s.force_encoding(Encoding::UTF_8)
    end

    # glibc's gettext has no pgettext of its own; GNU gettext's own library
    # (and every binding over it, including Rust's gettext-rs pgettext! that
    # upstream's shortcuts dialog uses) implements context the same way: the
    # context and the msgid are joined with EOT (\x04) into one lookup key
    # that msgfmt compiles the .mo's msgctxt entries under, and the context
    # prefix is stripped back off before the result is returned. Falling back
    # to the bare msgid, as here, is exactly what an unmatched lookup already
    # does one level up, in Lib.gettext itself.
    CONTEXT_GLUE = "\x04"

    def self.translate_with_context(context, text)
      setup
      key = "#{context}#{CONTEXT_GLUE}#{text}"
      result = Lib.gettext(key).to_s.force_encoding(Encoding::UTF_8)
      case result
      when key
        text.to_s
      else
        result
      end
    end
  end

  # Gettext gives a class the two shorthands the translated strings are marked
  # with, as upstream marks its own with gettext() and N_().
  module Gettext
    private

      def _(text) = I18n.translate(text)

      # Upstream's gettext-rs pgettext!(context, msgid): the msgctxt-qualified
      # lookup, for a string that is ambiguous on its own (as "General" is,
      # outside the shortcuts window it names a section of).
      def C_(context, text) = I18n.translate_with_context(context, text)

      # Marks a string for extraction without looking it up, for a table built
      # at load time whose strings are translated where they are shown.
      def N_(text) = text
  end
end
