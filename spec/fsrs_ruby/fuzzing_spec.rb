# frozen_string_literal: true

RSpec.describe 'Interval fuzzing' do
  let(:now) { Time.parse('2024-01-01T00:00:00.000Z') }

  def mature_card(stability: 100.0)
    FsrsRuby::Card.new(
      due: now,
      stability: stability,
      difficulty: 5.0,
      reps: 5,
      state: FsrsRuby::State::REVIEW,
      last_review: now - (stability * 86_400)
    )
  end

  describe 'the seed strategy' do
    it 'is wired up by default so the algorithm seeds its PRNG deterministically' do
      fsrs = FsrsRuby.new(enable_fuzz: true)
      fsrs.next(FsrsRuby.create_empty_card(now), now, FsrsRuby::Rating::EASY)

      expect(fsrs.seed).not_to be_nil
    end

    it 'uses a caller-supplied strategy when one is given' do
      fsrs = FsrsRuby.new(enable_fuzz: true)
      fsrs.use_strategy(:seed, ->(_scheduler) { 'card-42' })
      fsrs.next(FsrsRuby.create_empty_card(now), now, FsrsRuby::Rating::EASY)

      expect(fsrs.seed).to eq('card-42')
    end
  end

  describe 'spread across cards' do
    it 'gives identical cards different due dates when seeded per card' do
      dues = Array.new(20) do |i|
        fsrs = FsrsRuby.new(enable_fuzz: true)
        fsrs.use_strategy(:seed, ->(_scheduler) { "card-#{i}" })
        fsrs.next(mature_card, now, FsrsRuby::Rating::GOOD).card.due.to_date
      end

      expect(dues.uniq.size).to be > 1
    end

    it 'keeps every fuzzed interval inside the documented fuzz range' do
      unfuzzed = FsrsRuby.new(enable_fuzz: false)
                         .next(mature_card, now, FsrsRuby::Rating::GOOD).card
      base_days = (unfuzzed.due - now) / 86_400.0
      range = FsrsRuby::Helpers.get_fuzz_range(base_days, 0, 36_500)

      dues = Array.new(20) do |i|
        fsrs = FsrsRuby.new(enable_fuzz: true)
        fsrs.use_strategy(:seed, ->(_scheduler) { "card-#{i}" })
        (fsrs.next(mature_card, now, FsrsRuby::Rating::GOOD).card.due - now) / 86_400.0
      end

      expect(dues.min).to be >= range[:min_ivl] - 1
      expect(dues.max).to be <= range[:max_ivl] + 1
    end
  end

  describe 'the default strategy, and why callers should override it' do
    it 'derives the same seed for cards sharing a review instant and state' do
      seeds = Array.new(5) do
        fsrs = FsrsRuby.new(enable_fuzz: true)
        fsrs.next(mature_card, now, FsrsRuby::Rating::GOOD)
        fsrs.seed
      end

      expect(seeds.uniq.size).to eq(1)
    end

    it 'therefore clumps a batch scheduled at one instant onto a single day' do
      dues = Array.new(10) do
        FsrsRuby.new(enable_fuzz: true)
                .next(mature_card, now, FsrsRuby::Rating::GOOD).card.due.to_date
      end

      expect(dues.uniq.size).to eq(1)
    end

    it 'spreads that same batch once seeded per card' do
      dues = Array.new(10) do |i|
        fsrs = FsrsRuby.new(enable_fuzz: true)
        fsrs.use_strategy(:seed, FsrsRuby::Strategies.gen_seed_strategy_with_card_id(:reps))
        card = mature_card
        card.reps = i
        fsrs.next(card, now, FsrsRuby::Rating::GOOD).card.due.to_date
      end

      expect(dues.uniq.size).to be > 1
    end
  end

  describe 'reproducibility' do
    it 'returns the same due date for the same seed' do
      results = Array.new(2) do
        fsrs = FsrsRuby.new(enable_fuzz: true)
        fsrs.use_strategy(:seed, ->(_scheduler) { 'stable-seed' })
        fsrs.next(mature_card, now, FsrsRuby::Rating::GOOD).card.due
      end

      expect(results.first).to eq(results.last)
    end
  end

  describe 'when fuzzing is disabled' do
    it 'returns the unfuzzed interval every time' do
      dues = Array.new(5) do
        FsrsRuby.new(enable_fuzz: false)
                .next(mature_card, now, FsrsRuby::Rating::GOOD).card.due
      end

      expect(dues.uniq.size).to eq(1)
    end
  end
end
