# frozen_string_literal: true

require 'json'

# The companion to ts_conformance_spec: there every review lands exactly on the
# card's due date, which is the one case real learners never manage. These
# scenarios answer early, answer late, and answer the same card several times
# inside one sitting -- the paths where elapsed-time handling actually matters.
RSpec.describe 'Conformance with ts-fsrs, off schedule' do
  OFF_SCHEDULE = JSON.parse(
    File.read(File.expand_path('../fixtures/ts_off_schedule.json', __dir__))
  ).freeze

  GRADES = {
    'Again' => FsrsRuby::Rating::AGAIN,
    'Hard' => FsrsRuby::Rating::HARD,
    'Good' => FsrsRuby::Rating::GOOD,
    'Easy' => FsrsRuby::Rating::EASY
  }.freeze

  EPSILON = 1e-6
  ORIGIN = Time.parse('2024-01-01T00:00:00.000Z')

  OFF_SCHEDULE['scenarios'].each do |scenario|
    it "matches ts-fsrs for #{scenario['label']}" do
      fsrs = FsrsRuby.new(enable_fuzz: false)
      card = FsrsRuby.create_empty_card(ORIGIN)

      scenario['steps'].each_with_index do |step, index|
        review_time = Time.parse(step['review_time'])
        card = fsrs.next(card, review_time, GRADES.fetch(step['rating'])).card
        want = step['output']

        aggregate_failures "step #{index + 1} (#{step['rating']})" do
          expect(card.state).to eq(want['state'])
          expect(card.reps).to eq(want['reps'])
          expect(card.lapses).to eq(want['lapses'])
          expect(card.stability).to be_within(EPSILON).of(want['stability'])
          expect(card.difficulty).to be_within(EPSILON).of(want['difficulty'])
          expect(card.due.utc.iso8601(3)).to eq(Time.parse(want['due']).utc.iso8601(3))
        end
      end
    end
  end

  # The defect that made this harness worth building lived in a different
  # implementation, but it is the shape of failure this exists to catch: a
  # scheduler that inflates intervals while still returning plausible numbers.
  # The broken one grew 2 days -> 91 -> 2093 -> 31920 on consecutive Good
  # ratings. Bounding the growth ratio catches that without pinning exact
  # values, which the conformance specs already cover.
  it 'grows intervals at a bounded rate under repeated Good ratings' do
    fsrs = FsrsRuby.new(enable_fuzz: false)
    card = FsrsRuby.create_empty_card(ORIGIN)
    now = ORIGIN

    intervals = Array.new(6) do
      card = fsrs.next(card, now, FsrsRuby::Rating::GOOD).card
      days = (card.due - now) / 86_400.0
      now = card.due
      days
    end

    graduated = intervals.drop_while { |days| days < 1 }
    ratios = graduated.each_cons(2).map { |before, after| after / before }

    expect(ratios).to all(be < 10)
  end

  it 'never schedules beyond the configured maximum interval' do
    fsrs = FsrsRuby.new(enable_fuzz: false, maximum_interval: 180)
    card = FsrsRuby.create_empty_card(ORIGIN)
    now = ORIGIN

    intervals = Array.new(8) do
      card = fsrs.next(card, now, FsrsRuby::Rating::EASY).card
      days = (card.due - now) / 86_400.0
      now = card.due
      days
    end

    expect(intervals.max).to be <= 180
  end

  # A deliberate divergence from ts-fsrs, kept rather than matched. For Easy,
  # ts-fsrs takes max(good + 1, easy) after clamping, so it returns 182 for a
  # maximum_interval of 180 and 367 for 365 -- overshooting the limit the caller
  # set. This port clamps last and honours it. Recorded so the difference is a
  # decision on the record rather than a surprise later.
  it 'honours maximum_interval where ts-fsrs overshoots it' do
    fsrs = FsrsRuby.new(enable_fuzz: false, maximum_interval: 365)
    card = FsrsRuby.create_empty_card(ORIGIN)
    now = ORIGIN

    intervals = Array.new(8) do
      card = fsrs.next(card, now, FsrsRuby::Rating::EASY).card
      days = (card.due - now) / 86_400.0
      now = card.due
      days
    end

    expect(intervals.max).to eq(365)
  end
end
