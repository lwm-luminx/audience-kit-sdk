# frozen_string_literal: true

# Writes a Markdown digest of an audience's Soapbox news for a newsletter: a locale's latest, then national news.
#
#   AUDIENCEKIT_TOKEN=... AUDIENCEKIT_HOST=hotmess.social ruby examples/news_digest.rb Phoenix > digest.md
#
# The token is an application API key. Name a locale to read its news; without one, the first locale's.

require "audience-kit"

# Builds the digest.
module NewsDigest
  module_function

  # @param session [Audience::Kit::Session]
  # @param locale_name [String, nil]
  # @param first [Integer] how many local articles
  # @return [String] Markdown, empty when the audience has no Soapbox news
  def markdown(session, locale_name: nil, first: 10)
    locales = session.locales
    locale = locales.find { |candidate| candidate.name.casecmp?(locale_name.to_s) } || locales.first
    local = locale ? session.articles(locale_id: locale.id, first: first) : []
    national = session.national_articles(locale_id: locale&.id, first: 5)
    sections = []
    sections << section("News in #{locale.name}", local) if local.any?
    sections << section("Around the country", national) if national.any?
    sections.join("\n")
  end

  # @param heading [String]
  # @param articles [Array<Audience::Kit::Article>]
  # @return [String]
  def section(heading, articles)
    "## #{heading}\n\n#{articles.map { |article| entry(article) }.join("\n")}\n"
  end

  # One article: its title (linked to the publication's site for a teaser), source, summary and disclosure.
  # @param article [Audience::Kit::Article]
  # @return [String]
  def entry(article)
    title = article.teaser? && article.canonical_url ? "[#{article.title}](#{article.canonical_url})" : article.title
    source = [article.publication&.name, article.published_at&.strftime("%b %-d")].compact.join(", ")
    lines = ["- **#{title}**#{" (#{source})" unless source.empty?}"]
    lines << "  #{article.summary}" if article.summary
    lines << "  _#{article.disclosure}_" if article.disclosure
    lines.join("\n")
  end
end

puts NewsDigest.markdown(Audience::Kit::Session.from_env, locale_name: ARGV[0]) if $PROGRAM_NAME == __FILE__
