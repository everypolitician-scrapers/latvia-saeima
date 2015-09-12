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

def overlap(mem, term)
  mS = mem[:start_date].to_s.empty?  ? '0000-00-00' : mem[:start_date]
  mE = mem[:end_date].to_s.empty?    ? '9999-99-99' : mem[:end_date]
  tS = term[:start_date].to_s.empty? ? '0000-00-00' : term[:start_date]
  tE = term[:end_date].to_s.empty?   ? '9999-99-99' : term[:end_date]

  return unless mS < tE && mE > tS
  (s, e) = [mS, mE, tS, tE].sort[1,2]
  return { 
    _data: [mem, term],
    start_date: s == '0000-00-00' ? nil : s,
    end_date:   e == '9999-99-99' ? nil : e,
  }
end

def combine(h)
  into_name, into_data, from_name, from_data = h.flatten
  from_data.product(into_data).map { |a,b| overlap(a,b) }.compact.map { |h|
    data = h.delete :_data
    h.merge({ from_name => data.first[:id], into_name => data.last[:id] })
  }.sort_by { |h| h[:start_date] }
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

    email = nokomem.css('table.wholeForm a[href^="mailto:"]/@href').text.gsub('mailto:','') rescue ''
    person = { 
      id: URI(mp_page.current_url).path.split('/').last,
      name: nokomem.css('div.header3#ViewBlockTitle').text.tidy,
      photo: nokomem.css('td#photoHolder img/@src').text,
      email: email,
      source: mp_page.current_url,
    }
    person[:photo] = URI.join(url, person[:photo]).to_s unless person[:photo].to_s.empty?

    mems = nokomem.xpath('.//div[@class="header2" and contains(.,"Membership in the Saeima")]/following::table[1]//tr[td]').map do |tr|
      mtds = tr.css('td')
      mem = { 
        start_date: mtds[0].text.split('.').reverse.join('-'),
        end_date: mtds[1].text.split('.').reverse.join('-'),
        what: mtds[2].text,
        role: mtds[3].text,
      }
    end
    terms, groups = mems.partition { |m| m[:what].downcase.include? 'member of the saeima' }
    binding.pry if terms.count.zero? || groups.count.zero?

    binding.pry

    data = person.merge(front)
    puts data
    # ScraperWiki.save_sqlite([:id, :term], data)
  end
end
