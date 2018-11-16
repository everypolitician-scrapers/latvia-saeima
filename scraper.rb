#!/bin/env ruby
# frozen_string_literal: true

require 'combine_popolo_memberships'
require 'json5'
require 'nokogiri'
require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

@BASE = 'http://titania.saeima.lv'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

PERSON_URL = 'http://titania.saeima.lv/personal/deputati/saeima%s_depweb_public.nsf/0/%s?OpenDocument&lang=EN'
def scrape_person(data)
  url = PERSON_URL % [data[:term], data[:id]]
  nokomem = noko_for(url)

  email = nokomem.css('table.wholeForm a[href^="mailto:"]/@href').text.gsub('mailto:', '') rescue ''

  # TODO: add given name + family name from front page
  person = {
    id:     data[:id],
    name:   nokomem.css('div.header3#ViewBlockTitle').text.tidy,
    photo:  nokomem.css('td#photoHolder img/@src').text,
    email:  email,
    source: url.to_s,
  }
  person[:photo] = URI.join(url, person[:photo]).to_s unless person[:photo].to_s.empty?

  # TODO: get term from page
  # term = nokomem.css('script').map(&:text).find { |t| t.include? 'XX. SAEIMA' }[/'XX', '(\d+)'/, 1]

  mems = nokomem.css('.viewHolder script').text.split("\n").select { |l| l.include? 'drawWN' }.map { |l| JSON5.parse(l[/({.*?})/, 1].delete('\\')) }

  # TODO: Cabinet & Committees & other types of memberships
  type10 = mems.select { |m| m['strLvlTp'] == '10' }
  type2  = mems.select { |m| m['strLvlTp'] == '2' }
  if type2.empty? || type10.empty?
    warn "No memberships in #{url}"
    return
  end

  group_mems = type2.map do |r|
    {
      id:         r['str'].sub(' parliamentary group', ''),
      start_date: r['dtF'].split('.').reverse.join('-'),
      end_date:   r['dtT'].split('.').reverse.join('-'),
      role:       r['position'],
    }
  end

  saeima_mems = type10.map do |r|
    {
      id:         data[:term],
      start_date: r['dtF'].split('.').reverse.join('-'),
      end_date:   r['dtT'].split('.').reverse.join('-'),
    }
  end

  CombinePopoloMemberships.combine(term: saeima_mems, party: group_mems).each do |mem|
    %i[role].each { |i| mem.delete(i) }

    info = person.merge(data).merge(mem)
    puts info.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h if ENV['MORPH_DEBUG']
    ScraperWiki.save_sqlite(%i[id term party start_date], info)
  end
end

def scrape_list(term, fragment, type)
  url = URI.join(@BASE, fragment)
  noko = noko_for(url)

  ppl = noko.css('.viewHolderText').text.split("\n").select { |l| l.include? type }.map { |l| JSON5.parse(l[/({.*?})/, 1]) }

  ppl.each do |row|
    data = {
      id:          row['unid'],
      given_name:  row['name'],
      family_name: row['sname'],
      term:        term,

      # TODO: build these up so we can get the IDs
      # current_group: row['lst'],
      # current_group_id: row['shortStr'],
    }
    scrape_person(data)
  end
end

pages = [
  [12, '/personal/deputati/saeima12_depweb_public.nsf/deputies?OpenView&lang=EN&count=1000', 'drawDep'],
  [12, '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=1&lang=EN&count=1000', 'drawMand'],
  [12, '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=2&lang=EN&count=1000', 'drawMand'],
  # [ 11, '/personal/deputati/saeima11_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=2&lang=EN&count=1000', 'drawMand' ],
  # [ 10, '/personal/deputati/saeima10_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=2&lang=EN&count=1000', 'drawMand' ],
]
pages.each { |term, link, type| scrape_list(term, link, type) }
