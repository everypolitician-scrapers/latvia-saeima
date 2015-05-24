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
  def trim
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
  page = visit url

  noko = Nokogiri::HTML(page.html)

  noko.css('table#tableWithContent tr[class*="Row"]').each do |row|
    tds = row.css('td')
    mp_link = row.attr('onclick').split("'")[1]

    # puts "#{mp_link}".red
    mp_page = visit mp_link

    mem_table = ''
    if mp_page.has_xpath? ('//frame[@name="topFrame"]') 
      framesrc = find(:xpath, '//frame[@name="topFrame"]')['src']
      frame_url = URI.join(mp_link, framesrc)
      # warn "Frame: #{frame_url}".red
      mp_page = visit frame_url
    end

    mem_table = find(:xpath, './/div[@class="header2" and contains(.,"Membership in the Saeima")]/following::table[1]')

    memberships = mem_table.all(:xpath, './/td[text() = "Member"]')
    if memberships.count.zero?
      memberships = mem_table.all(:xpath, './/td[contains(.,"Chair")]')
      raise "Erk! No memberships for #{mp_page.current_url}" if memberships.count.zero?
    end

    raise "Too many memberships for #{mp_page.current_url}" if memberships.count > 1

    mtds = memberships.first.all(:xpath, '../td')
    start_date = mtds[0].text
    end_date = mtds[1].text
    faction = mtds[2].text
    email = find('table.wholeForm a[href^=mailto]')['href'].gsub('mailto:','') rescue ''
    binding.pry

    data = { 
      id: URI(mp_page.current_url).path.split('/').last,
      name: find('div.header3#ViewBlockTitle').text,
      first_name: tds[1].text.strip,
      family_name: tds[2].text.strip,
      faction: tds[3].text.strip,
      photo: find('td#photoHolder img')['src'],
      email: email,
      faction: faction,
      start_date: start_date,
      end_date: end_date,
      term: 12,
      source: mp_page.current_url,
    }
    data[:photo].prepend @BASE unless data[:photo].to_s.empty?
    ScraperWiki.save_sqlite([:id, :term], data)

    puts data
  end
end
