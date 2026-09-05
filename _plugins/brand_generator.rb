require 'json'

module Jekyll
  module FrcUtil
    def self.rawdata_dir(site)
      File.join(site.source, '_rawdata')
    end
  end

  # ── 데이터 로드 (한 번만) ──────────────────────────────
  class BrandDataGenerator < Generator
    safe true
    priority :highest

    def generate(site)
      return if site.data['brand_all']

      dir = FrcUtil.rawdata_dir(site)
      shard_files = Dir.glob(File.join(dir, 'industry_*.json'))
      all_items = []
      by_lclas = Hash.new { |h, k| h[k] = [] }

      shard_files.each do |f|
        lclas = File.basename(f, '.json').sub('industry_', '')
        items = JSON.parse(File.read(f, encoding: 'utf-8'))
        by_lclas[lclas] = items
        all_items.concat(items)
      end

      site.data['brand_all'] = all_items
      site.data['brand_by_lclas'] = by_lclas
      Jekyll.logger.info "BrandGenerator:", "총 #{all_items.size}개 브랜드 로드 (#{by_lclas.size}개 대분류)"
    end
  end

  # ── 대분류 인덱스 페이지 ───────────────────────────────
  class LclasPageGenerator < Generator
    safe true
    priority :normal

    def generate(site)
      by_lclas = site.data['brand_by_lclas'] || {}
      by_lclas.each do |lclas, items|
        site.pages << LclasPage.new(site, lclas, items)
      end
      Jekyll.logger.info "BrandGenerator:", "대분류 페이지 #{by_lclas.size}개 생성"
    end
  end

  class LclasPage < Page
    def initialize(site, lclas, items)
      @site = site
      @base = site.source
      @dir  = "industry/#{lclas}"
      @name = 'index.html'
      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'lclas.html')

      by_mlsfc = Hash.new(0)
      items.each { |it| by_mlsfc[it['mlsfc']] += 1 }
      mlsfc_list = by_mlsfc.map { |nm, cnt| { 'name' => nm, 'count' => cnt } }.sort_by { |m| -m['count'] }

      self.data['lclas'] = lclas
      self.data['mlsfcList'] = mlsfc_list
      self.data['totalCount'] = items.size
      self.data['layout'] = 'lclas'
      self.data['title'] = "#{lclas}업종 프랜차이즈 창업비용 — 업종별 목록"
      self.data['description'] = "#{lclas} 업종 프랜차이즈 브랜드 #{items.size}개의 가맹비·교육비 등 창업비용을 업종별로 확인하세요."
    end
  end

  # ── 중분류 페이지 (브랜드 카드 목록) ────────────────────
  class MlsfcPageGenerator < Generator
    safe true
    priority :normal

    def generate(site)
      by_lclas = site.data['brand_by_lclas'] || {}
      count = 0
      by_lclas.each do |lclas, items|
        grouped = Hash.new { |h, k| h[k] = [] }
        items.each { |it| grouped[it['mlsfc']] << it }
        grouped.each do |mlsfc, list|
          site.pages << MlsfcPage.new(site, lclas, mlsfc, list)
          count += 1
        end
      end
      Jekyll.logger.info "BrandGenerator:", "중분류 페이지 #{count}개 생성"
    end
  end

  class MlsfcPage < Page
    def initialize(site, lclas, mlsfc, items)
      @site = site
      @base = site.source
      @dir  = "industry/#{lclas}/#{mlsfc}"
      @name = 'index.html'
      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'mlsfc.html')

      self.data['lclas'] = lclas
      self.data['mlsfc'] = mlsfc
      self.data['items'] = items.sort_by { |it| it['brandNm'] }
      self.data['totalCount'] = items.size
      self.data['layout'] = 'mlsfc'
      self.data['title'] = "#{mlsfc} 프랜차이즈 창업비용 비교 (#{items.size}개 브랜드)"
      self.data['description'] = "#{lclas} > #{mlsfc} 프랜차이즈 브랜드 #{items.size}개의 가맹비·교육비·평균매출을 비교해보세요."
    end
  end

  # ── 개별 브랜드 상세 페이지 ──────────────────────────────
  class BrandPageGenerator < Generator
    safe true
    priority :normal

    def generate(site)
      all_items = site.data['brand_all'] || []
      all_items.each { |it| site.pages << BrandPage.new(site, it) }
      Jekyll.logger.info "BrandGenerator:", "브랜드 상세 페이지 #{all_items.size}개 생성"
    end
  end

  class BrandPage < Page
    def initialize(site, it)
      @site = site
      @base = site.source
      @dir  = "brand/#{it['slug']}"
      @name = 'index.html'
      self.process(@name)
      self.read_yaml(File.join(@base, '_layouts'), 'brand.html')
      self.data.merge!(it)
      self.data['layout'] = 'brand'
      self.data['title'] = "#{it['brandNm']} 가맹비·창업비용 — #{it['mlsfc']} | #{it['corpNm']}"
      extra = it['smtnAmt'] ? "총 창업비용 약 #{it['smtnAmt']}, " : ""
      self.data['description'] = "#{it['brandNm']}(#{it['corpNm']}) #{extra}가맹점 수, 평균매출, 가맹비·교육비·보증금 정보를 확인하세요."
    end
  end
end
