#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'capybara'
require 'capybara/poltergeist'
require 'nokogiri'

require 'colorize'
require 'pry'

include Capybara::DSL
Capybara.default_driver = :poltergeist

@BASE = 'http://titania.saeima.lv'

class String
  def tidy
    self.gsub(/[[:space:]]/,' ').strip
  end
end

pages = [
  '/personal/deputati/saeima12_depweb_public.nsf/deputies?OpenView&lang=EN&count=1000',
  '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=1&lang=EN&count=1000',
  '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=2&lang=EN&count=1000',
]

pages.each do |link|
  url = @BASE + link
  puts url
  page = visit url

  noko = Nokogiri::HTML(page.html)

  noko.css('table#tableWithContent tr[class*="Row"]').each do |row|
    tds = row.css('td')
    front = {
      first_name: tds[1].text.tidy,
      family_name: tds[2].text.tidy,
      current_group: tds[3].text.tidy,
      source: row.attr('onclick').split("'")[1],
    }

    # puts "#{mp_link}".red
    mp_page = visit front[:source]
    mem_table = ''
    if mp_page.has_xpath? ('//frame[@name="topFrame"]') 
      framesrc = find(:xpath, '//frame[@name="topFrame"]')['src']
      frame_url = URI.join(front[:source], framesrc)
      # warn "Frame: #{frame_url}".red
      mp_page = visit frame_url
    end
    nokomem = Nokogiri::HTML(mp_page.html)

    mems = nokomem.xpath('.//div[@class="header2" and contains(.,"Membership in the Saeima")]/following::table[1]//tr[td]').map do |tr|
      mtds = tr.css('td')
      mem = { 
        start_date: mtds[0].text.split('.').reverse.join('-'),
        end_date: mtds[1].text.split('.').reverse.join('-'),
        what: mtds[2].text,
        role: mtds[3].text,
      }
    end
    binding.pry if mems.count.zero?
    raise "Erk! No memberships for #{mp_page.current_url}" if mems.count.zero?
    terms, groups = mems.partition { |m| m[:what].downcase.include? 'member of the saeima' }
    binding.pry if terms.count.zero?
    raise "Erk! No terms for #{mp_page.current_url}" if terms.count.zero?
    binding.pry if groups.count.zero?
    raise "Erk! No groups for #{mp_page.current_url}" if groups.count.zero?

    email = nokomem.css('table.wholeForm a[href^="mailto:"]/@href').text.gsub('mailto:','') rescue ''
    person = { 
      id: URI(mp_page.current_url).path.split('/').last,
      name: nokomem.css('div.header3#ViewBlockTitle').text.tidy,
      photo: nokomem.css('td#photoHolder img/@src').text,
      email: email,
      source: mp_page.current_url,
    }
    person[:photo] = URI.join(url, person[:photo]).to_s unless person[:photo].to_s.empty?

    data = person.merge(front)
    puts data
    # ScraperWiki.save_sqlite([:id, :term], data)
  end
end
