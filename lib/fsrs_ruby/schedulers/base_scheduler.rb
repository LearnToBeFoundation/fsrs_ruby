# frozen_string_literal: true

module FsrsRuby
  module Schedulers
    # Base scheduler implementing template method pattern
    class BaseScheduler
      attr_reader :last, :current, :review_time, :algorithm, :strategies, :elapsed_days

      def initialize(card, now, algorithm, strategies = {})
        @last = card.is_a?(Card) ? card : TypeConverter.card(card)
        @current = @last.clone
        @review_time = now.is_a?(Time) ? now : TypeConverter.time(now)
        @algorithm = algorithm
        @strategies = strategies
        @next_cache = {}

        init
      end

      # Preview all possible outcomes
      # @return [Hash] { Rating::AGAIN =>, Rating::HARD =>, Rating::GOOD =>, Rating::EASY => }
      def preview
        {
          Rating::AGAIN => review(Rating::AGAIN),
          Rating::HARD => review(Rating::HARD),
          Rating::GOOD => review(Rating::GOOD),
          Rating::EASY => review(Rating::EASY)
        }
      end

      # Apply specific rating
      # @param grade [Integer] Rating (1-4)
      # @return [RecordLogItem] { card:, log: }
      def review(grade)
        raise ArgumentError, "Invalid grade: #{grade}" unless (Rating::AGAIN..Rating::EASY).cover?(grade)

        return @next_cache[grade] if @next_cache.key?(grade)

        result = case @current.state
                 when State::NEW
                   new_state(grade)
                 when State::LEARNING, State::RELEARNING
                   learning_state(grade)
                 when State::REVIEW
                   review_state(grade)
                 else
                   raise "Unknown state: #{@current.state}"
                 end

        @next_cache[grade] = result
        result
      end

      protected

      def init
        @elapsed_days = if @last.last_review
                          Helpers.date_diff(@review_time, @last.last_review, :days)
                        else
                          0
                        end

        @current.last_review = @review_time
        @current.reps += 1

        @seed_strategy = @strategies[:seed] || Strategies.method(:default_init_seed_strategy)
        @algorithm.seed = @seed_strategy.call(self)
      end

      # Build review log
      # @param rating [Integer] Rating given
      # @return [ReviewLog]
      def build_log(rating)
        ReviewLog.new(
          rating: rating,
          state: @last.state,
          due: @last.due,
          stability: @last.stability,
          difficulty: @last.difficulty,
          elapsed_days: @elapsed_days,
          last_elapsed_days: @last.scheduled_days,
          scheduled_days: @current.scheduled_days,
          learning_steps: @current.learning_steps,
          review: @review_time
        )
      end

      # Calculate next difficulty and stability
      # @param interval [Integer] Elapsed interval
      # @return [Hash] { difficulty:, stability: }
      def next_ds(interval = 0)
        @algorithm.next_state(
          { difficulty: @last.difficulty, stability: @last.stability },
          interval,
          @current.state == State::NEW ? Rating::GOOD : @current.state
        )
      end

      # Template methods (to be overridden by subclasses)
      def new_state(grade)
        raise NotImplementedError, "#{self.class} must implement #new_state"
      end

      def learning_state(grade)
        raise NotImplementedError, "#{self.class} must implement #learning_state"
      end

      def review_state(grade)
        raise NotImplementedError, "#{self.class} must implement #review_state"
      end
    end
  end
end
