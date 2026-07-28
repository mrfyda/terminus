# frozen_string_literal: true

# Thin REST wrappers for closed-source Core API clients that vendored plugins
# reference as ::APIClients::<Name>.  Each class is intentionally minimal —
# only the methods actually called by the plugins in vendor/plugins/lib/ are
# implemented.  Return shapes mirror the Notion/Shopify JSON payloads so
# plugin code that digs into them continues to work without modification.
#
# Auth note: all clients here use user-pasted API tokens (no OAuth flows).

require "httparty"
require "logger"

# ---------------------------------------------------------------------------
# ShopifyAPI::Context lazy bootstrap
#
# ShopifyAPI::Clients::Rest::Admin requires Context.setup to be called before
# any session is created.  Private-app admin tokens don't need real OAuth
# credentials, so we use placeholder values; only the api_version matters for
# routing.  We call setup at most once (idempotent guard) so that a second
# require of this file in the same process does not reset a real config.
# ---------------------------------------------------------------------------
require "shopify_api"

unless ShopifyAPI::Context.api_version.present?
  ShopifyAPI::Context.setup(
    api_key:        ENV.fetch("SHOPIFY_API_KEY", "terminus_native_plugin"),
    api_secret_key: ENV.fetch("SHOPIFY_API_SECRET", "terminus_native_plugin"),
    api_version:    "2025-01",
    is_private:     true,
    is_embedded:    false,
    scope:          [],
    log_level:      :warn
  )
end

module APIClients
  # -------------------------------------------------------------------------
  # Notion REST client (api.notion.com/v1)
  #
  # Wraps the public Notion Integration API.  Tokens are internal-integration
  # Bearer tokens that users paste into the plugin settings.
  # -------------------------------------------------------------------------
  class Notion
    include HTTParty

    NOTION_API_BASE    = "https://api.notion.com/v1"
    NOTION_API_VERSION = "2022-06-28"

    def initialize(access_token)
      @access_token = access_token
      @headers = {
        "Authorization"  => "Bearer #{access_token}",
        "Content-Type"   => "application/json",
        "Notion-Version" => NOTION_API_VERSION
      }
    end

    # POST /databases/{id}/query
    # Returns the raw Notion response hash (keys: 'results', 'next_cursor',
    # 'has_more').  The plugin reads response['results'] directly.
    def query_database(database_id, page_size: nil, sorts: nil, filter: nil)
      body = {}
      body["page_size"] = page_size if page_size
      body["sorts"]     = sorts     if sorts
      body["filter"]    = filter    if filter

      response = HTTParty.post(
        "#{NOTION_API_BASE}/databases/#{database_id}/query",
        headers: @headers,
        body:    body.to_json,
        timeout: 30
      )
      response.parsed_response
    end

    # GET /pages/{id}
    # Returns the raw Notion page object (keys: 'properties', 'url',
    # 'last_edited_time', etc.).
    def get_page_info(page_id)
      response = HTTParty.get(
        "#{NOTION_API_BASE}/pages/#{page_id}",
        headers: @headers,
        timeout: 30
      )
      response.parsed_response
    end

    # GET /blocks/{id}/children
    # Returns the raw Notion block list (keys: 'results', 'next_cursor',
    # 'has_more').  The plugin reads response['results'] directly.
    def get_page_blocks(page_id, page_size: nil)
      query = {}
      query[:page_size] = page_size if page_size

      response = HTTParty.get(
        "#{NOTION_API_BASE}/blocks/#{page_id}/children",
        headers: @headers,
        query:   query,
        timeout: 30
      )
      response.parsed_response
    end

    # --- Class-method helpers used by the plugin's setup UI ------------------
    # These are called only by Plugins::Notion class methods to populate
    # dropdown options; they return simple arrays of hashes.

    def list_databases
      search("", filter_type: "database")
    end

    def list_pages
      search("", filter_type: "page")
    end

    def search_databases(query = "")
      search(query, filter_type: "database")
    end

    def search_pages(query = "")
      search(query, filter_type: "page")
    end

    private

    # POST /search — returns an array of {id:, title:} hashes.
    def search(query, filter_type: nil)
      body = { query: query }
      body[:filter] = { value: filter_type, property: "object" } if filter_type

      response = HTTParty.post(
        "#{NOTION_API_BASE}/search",
        headers: @headers,
        body:    body.to_json,
        timeout: 30
      )
      (response.parsed_response["results"] || []).map do |item|
        title = extract_title(item)
        { "id" => item["id"], "title" => title }
      end
    rescue StandardError
      []
    end

    def extract_title(item)
      props = item["properties"] || {}
      title_prop = props.values.find { |v| v.is_a?(Hash) && v["type"] == "title" }
      return item["id"] unless title_prop

      title_prop["title"]&.map { |t| t["plain_text"] }&.join || item["id"]
    end
  end
end
