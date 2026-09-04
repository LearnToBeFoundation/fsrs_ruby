# frozen_string_literal: true

RSpec.describe FsrsRuby::Strategies do
  describe '.default_init_seed_strategy' do
    it 'generates seed from review time and card properties' do
      now = Time.parse('2024-01-15T12:00:00Z')
      card = FsrsRuby::Card.new(
        due: now,
        reps: 5,
        difficulty: 2.5,
        stability: 10.0
      )

      fsrs = FsrsRuby.new
      scheduler = fsrs.send(:get_scheduler, card, now)

      seed = described_class.default_init_seed_strategy(scheduler)

      expect(seed).to be_a(String)
      expect(seed).to include(now.to_i.to_s)
      expect(seed).to include('6') # reps (incremented by scheduler)
      # Should include multiplication of difficulty and stability
      mul = (2.5 * 10.0).round(2)
      expect(seed).to include(mul.to_s)
    end
  end

  describe '.gen_seed_strategy_with_card_id' do
    it 'generates seed strategy proc' do
      strategy = described_class.gen_seed_strategy_with_card_id(:custom_field)

      expect(strategy).to be_a(Proc)
      expect(strategy).to respond_to(:call)
    end

    it 'generates seed from card ID field' do
      # Create a mock scheduler with a card that responds to the field
      mock_card = FsrsRuby::Card.new(due: Time.now, reps: 5)

      # Add custom field to the mock card
      def mock_card.card_id
        'test_card_123'
      end

      mock_scheduler = double('Scheduler', current: mock_card)

      strategy = described_class.gen_seed_strategy_with_card_id(:card_id)
      seed = strategy.call(mock_scheduler)

      expect(seed).to eq('test_card_1235')
    end
  end

  # The two examples above call the strategy directly, so they passed while
  # BaseScheduler#init assigned the strategy and never invoked it. These check
  # the wiring instead: that a review actually seeds the algorithm.
  describe 'wiring into a review' do
    let(:now) { Time.parse('2024-01-01T00:00:00.000Z') }

    it 'seeds the algorithm from the default strategy when no custom one is set' do
      fsrs = FsrsRuby.new(enable_fuzz: true)

      fsrs.next(FsrsRuby.create_empty_card(now), now, FsrsRuby::Rating::GOOD)

      expect(fsrs.seed).not_to be_nil
    end

    it 'seeds the algorithm from a caller-supplied strategy when one is set' do
      fsrs = FsrsRuby.new(enable_fuzz: true)
      fsrs.use_strategy(:seed, ->(_scheduler) { 'card-42' })

      fsrs.next(FsrsRuby.create_empty_card(now), now, FsrsRuby::Rating::GOOD)

      expect(fsrs.seed).to eq('card-42')
    end
  end
end
