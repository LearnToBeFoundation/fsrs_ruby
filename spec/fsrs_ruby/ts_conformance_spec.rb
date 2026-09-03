# frozen_string_literal: true

require 'json'

# Walks every sequence recorded from ts-fsrs and asserts the Ruby port lands on
# the same card state at every step. Fuzzing is off in the fixture, so these are
# exact comparisons rather than tolerances.
RSpec.describe 'Conformance with ts-fsrs' do
  FIXTURE = JSON.parse(
    File.read(File.expand_path('../fixtures/ts_sequences.json', __dir__))
  ).freeze

  RATINGS = {
    'Again' => FsrsRuby::Rating::AGAIN,
    'Hard' => FsrsRuby::Rating::HARD,
    'Good' => FsrsRuby::Rating::GOOD,
    'Easy' => FsrsRuby::Rating::EASY
  }.freeze

  TOLERANCE = 1e-6

  it 'was generated with fuzzing disabled' do
    expect(FIXTURE.dig('metadata', 'enable_fuzz')).to be(false)
  end

  FIXTURE['sequences'].each do |scenario|
    label = scenario['sequence'].join(' -> ')

    it "matches ts-fsrs for #{label}" do
      fsrs = FsrsRuby.new(enable_fuzz: false)
      card = FsrsRuby.create_empty_card(Time.parse('2024-01-01T00:00:00.000Z'))

      scenario['steps'].each_with_index do |step, index|
        review_time = Time.parse(step['review_time'])
        card = fsrs.next(card, review_time, RATINGS.fetch(step['rating'])).card
        want = step['output']
        at = "step #{index + 1} of #{label}"

        aggregate_failures at do
          expect(card.state).to eq(want['state'])
          expect(card.reps).to eq(want['reps'])
          expect(card.lapses).to eq(want['lapses'])
          expect(card.stability).to be_within(TOLERANCE).of(want['stability'])
          expect(card.difficulty).to be_within(TOLERANCE).of(want['difficulty'])
          expect(card.due.utc.iso8601(3)).to eq(Time.parse(want['due']).utc.iso8601(3))
        end
      end
    end
  end
end
