#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'capybara'
require 'capybara/poltergeist'
require 'nokogiri'
require 'combine_popolo_memberships'

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
  # '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=1&lang=EN&count=1000',
  # '/personal/deputati/saeima12_depweb_public.nsf/deputiesByMandate?OpenView&restricttocategory=2&lang=EN&count=1000',
]

pages.each do |link|
  url = @BASE + link
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

    email = nokomem.css('table.wholeForm a[href^="mailto:"]/@href').text.gsub('mailto:','') rescue ''
    person = { 
      id: URI(mp_page.current_url).path.split('/').last,
      name: nokomem.css('div.header3#ViewBlockTitle').text.tidy,
      photo: nokomem.css('td#photoHolder img/@src').text,
      email: email,
      term: nokomem.css('.mainInfo .header3').text[/Activity during the (\d+)\w+ Saeima/, 1],
      source: mp_page.current_url,
    }
    person[:photo] = URI.join(url, person[:photo]).to_s unless person[:photo].to_s.empty?

    mems = nokomem.xpath('.//div[@class="header2" and contains(.,"Membership in the Saeima")]/following::table[1]//tr[not(@class="tblHead")]').map do |tr|
      mtds = tr.css('td')
      mem = { 
        id: mtds[2].text.tidy,
        start_date: mtds[0].text.split('.').reverse.join('-'),
        end_date: mtds[1].text.split('.').reverse.join('-'),
        role: mtds[3].text.tidy,
        style: tr.attr('style'),
      }
    end
    groups, terms = mems.partition { |m| m[:style].downcase.include? 'bold' }
    binding.pry if terms.count.zero? || groups.count.zero?

    puts person[:name]

    CombinePopoloMemberships.combine(note: terms, party: groups).each do |mem|
      %i(role style).each { |i| mem.delete(i) }
      data = person.merge(front).merge(mem)
      data[:party] = data[:party].sub(' parliamentary group','')
      ScraperWiki.save_sqlite([:id, :term, :party, :start_date], data)
    end
  end
end
