require 'json'

module Jekyll
  module FrcUtil
    def self.rawdata_dir(site)
      File.join(site.source, '_rawdata')
    end
  end

  # ── 창업비용 비교 계산 (업종 평균·순위·비슷한 비용대 브랜드) ──────────
  module FrcStats
    MIN_GROUP = 5   # 업종 내 창업비용 공개 브랜드가 이보다 적으면 비교 블록을 만들지 않음

    def self.mid(str)
      return nil if str.nil? || str.to_s.strip.empty?
      nums = str.to_s.scan(/\d+/).map(&:to_f)
      return nil if nums.empty?
      nums.size >= 2 ? (nums[0] + nums[1]) / 2.0 : nums[0]
    end

    def self.comma(n)
      n.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end

    # 만원 단위 숫자 → "1억 1,500만원" / "5,800만원"
    def self.fmt(v)
      v = v.round
      if v >= 10_000
        eok = v / 10_000
        rem = v % 10_000
        rem = (rem / 100.0).round * 100 if rem >= 1000
        rem > 0 ? "#{eok}억 #{comma(rem)}만원" : "#{eok}억원"
      else
        "#{comma(v)}만원"
      end
    end

    def self.build_groups(all_items)
      groups = Hash.new { |h, k| h[k] = [] }
      all_items.each do |it|
        m = mid(it['smtnAmt'])
        next unless m && m > 0
        groups[[it['lclas'], it['mlsfc']]] << [m, it]
      end
      groups.each_value { |v| v.sort_by! { |m, it| [m, it['brandNm'].to_s] } }
      groups
    end

    def self.group_summary(list)
      mids = list.map(&:first)
      sales = list.map { |_, it| mid(it['avrgSls']) }.compact.select { |v| v > 0 }
      { 'n' => list.size, 'avg' => mids.sum / mids.size, 'low' => list.first, 'high' => list.last,
        'salesAvg' => (sales.size >= 3 ? sales.sum / sales.size : nil) }
    end

    # 브랜드 한 곳의 비교 정보 (해당 없으면 nil)
    def self.compare(groups, it)
      list = groups[[it['lclas'], it['mlsfc']]]
      m = mid(it['smtnAmt'])
      return nil if list.nil? || list.size < MIN_GROUP || m.nil? || m <= 0
      sm = group_summary(list)
      rank = list.count { |x, _| x < m } + 1
      diff = (m - sm['avg']) / sm['avg'] * 100.0
      diff_txt = diff.abs < 1 ? '이 브랜드는 평균과 비슷한 수준입니다' : "이 브랜드는 평균보다 약 #{diff.abs.round}% #{diff > 0 ? '높습니다' : '낮습니다'}"
      text = "#{it['brandNm']}의 총 창업비용은 약 #{fmt(m)}이고, #{it['mlsfc']} 업종 창업비용 공개 브랜드 #{comma(sm['n'])}곳 중 낮은 순으로 #{comma(rank)}위입니다. 업종 평균은 약 #{fmt(sm['avg'])}이며 #{diff_txt}."
      sales = mid(it['avrgSls'])
      sales_txt = nil
      if sales && sales > 0
        sales_txt = "연 평균매출은 #{fmt(sales)}이며 총 창업비용의 약 #{(sales / m).round(1)}배입니다"
        sales_txt += sm['salesAvg'] ? "(업종 평균 연매출 약 #{fmt(sm['salesAvg'])}). 매출은 이익이 아니므로 임대료·인건비·재료비 등을 빼고 따져 보세요." : ". 매출은 이익이 아니므로 임대료·인건비·재료비 등을 빼고 따져 보세요."
      end
      peers = list.reject { |_, o| o['slug'] == it['slug'] }.sort_by { |x, o| [(x - m).abs, o['brandNm'].to_s] }.first(6).sort_by { |x, _| x }
      peer_rows = peers.map do |x, o|
        { 'brandNm' => o['brandNm'], 'slug' => o['slug'], 'cost' => fmt(x),
          'frcs' => (o['frcsCnt'].to_s.empty? ? nil : o['frcsCnt']) }
      end
      { 'text' => text, 'salesText' => sales_txt, 'peers' => peer_rows, 'n' => comma(sm['n']), 'rank' => rank,
        'avgText' => fmt(sm['avg']), 'selfText' => fmt(m) }
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
      site.data['frc_groups'] = FrcStats.build_groups(all_items)
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
      list = (site.data['frc_groups'] || {})[[lclas, mlsfc]]
      if list && list.size >= FrcStats::MIN_GROUP
        sm = FrcStats.group_summary(list)
        self.data['summary'] = "#{mlsfc} 업종에서 창업비용을 공개한 브랜드 #{FrcStats.comma(sm['n'])}곳의 평균 총 창업비용은 약 #{FrcStats.fmt(sm['avg'])}입니다. 가장 낮은 곳은 #{sm['low'][1]['brandNm']}(약 #{FrcStats.fmt(sm['low'][0])}), 가장 높은 곳은 #{sm['high'][1]['brandNm']}(약 #{FrcStats.fmt(sm['high'][0])})입니다."
        self.data['summarySales'] = sm['salesAvg'] ? "연 평균매출을 공개한 브랜드의 업종 평균은 약 #{FrcStats.fmt(sm['salesAvg'])}입니다." : nil
      end
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
      self.data['cmp'] = FrcStats.compare(site.data['frc_groups'] || {}, it)
      self.data['layout'] = 'brand'
      self.data['title'] = "#{it['brandNm']} 가맹비·창업비용 — #{it['mlsfc']} | #{it['corpNm']}"
      extra = it['smtnAmt'] ? "총 창업비용 약 #{it['smtnAmt']}, " : ""
      self.data['description'] = "#{it['brandNm']}(#{it['corpNm']}) #{extra}가맹점 수, 평균매출, 가맹비·교육비·보증금 정보를 확인하세요."
    end
  end
end
