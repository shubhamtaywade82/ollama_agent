#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv/load"
require "net/http"
require "json"

class CloudModelProbe
  CLOUD_API = "https://ollama.com"

  attr_reader :api_key

  def initialize(api_key: ENV["OLLAMA_API_KEY"])
    raise "Set OLLAMA_API_KEY in .env or environment" if api_key.nil? || api_key.strip.empty?

    @api_key = api_key
  end

  def run
    models = fetch_cloud_models
    puts "Found #{models.size} cloud models. Probing each...\n\n"

    results = models.map { |m| probe(m) }

    free = results.select { |r| r[:status] == :free }
    paid = results.select { |r| r[:status] == :paid }
    errors = results.select { |r| r[:status] == :error }

    print_section("FREE (accessible on your plan)", free)
    print_section("PAID (requires subscription)", paid)
    print_section("ERRORS (other failure)", errors) if errors.any?
  end

  private

  def fetch_cloud_models
    uri = URI("#{CLOUD_API}/api/tags")
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{api_key}"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 15) do |http|
      http.request(req)
    end

    data = JSON.parse(res.body)
    (data["models"] || []).map { |m| m["name"] }.compact
  rescue StandardError => e
    abort "Failed to fetch models: #{e.message}"
  end

  def probe(model_name)
    model_name = ensure_cloud_suffix(model_name)
    print "  Probing #{model_name}... "

    uri = URI("#{CLOUD_API}/api/chat")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req["Authorization"] = "Bearer #{api_key}"
    req.body = {
      model: model_name,
      messages: [{ role: "user", content: "hi" }],
      stream: false,
      options: { num_predict: 1 }
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) do |http|
      http.request(req)
    end

    status = case res.code
             when "200" then :free
             when "403" then :paid
             else :error
             end

    label = { free: "FREE", paid: "PAID", error: "ERR #{res.code}" }[status]
    puts label
    { name: model_name, status: status, code: res.code }
  rescue StandardError => e
    puts "TIMEOUT/ERROR"
    { name: model_name, status: :error, code: e.message }
  end

  def ensure_cloud_suffix(name)
    name.end_with?("-cloud") ? name : "#{name}-cloud"
  end

  def print_section(title, results)
    return if results.empty?

    puts "\n#{'=' * 60}"
    puts "  #{title}"
    puts '=' * 60
    results.each { |r| puts "  #{r[:name]}" }
  end
end

CloudModelProbe.new.run
