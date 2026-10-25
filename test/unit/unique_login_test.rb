# frozen_string_literal: true

# Runs without Redmine: `ruby test/unit/unique_login_test.rb`
require 'minitest/autorun'
require_relative '../../lib/redmine_proxyauth/unique_login'

class UniqueLoginTest < Minitest::Test
  Login = RedmineProxyauth::UniqueLogin

  def taken_logins
    @taken_logins ||= []
  end

  def login_for(email)
    Login.for(email, taken: ->(login) { taken_logins.include?(login) })
  end

  def test_uses_the_local_part_when_it_is_free
    assert_equal 'john', login_for('john@a.example')
  end

  def test_downcases_the_local_part
    assert_equal 'john.doe', login_for('John.Doe@a.example')
  end

  def test_a_second_person_with_the_same_local_part_gets_the_address_instead
    taken_logins << 'john'

    assert_equal 'john@b.example', login_for('john@b.example')
  end

  def test_falls_back_to_a_numbered_login_when_the_address_is_taken_too
    taken_logins.push('john', 'john@b.example')

    assert_equal 'john-1', login_for('john@b.example')
  end

  def test_keeps_counting_past_the_numbered_logins
    taken_logins.push('john', 'john@b.example')
    (1..9).each { |n| taken_logins << "john-#{n}" }

    assert_match(/\Ajohn-[0-9a-f]{8}\z/, login_for('john@b.example'))
  end

  def test_replaces_characters_redmine_does_not_allow_in_a_login
    assert_equal 'j-rg-m-ller', login_for('Jörg Müller@a.example')
  end

  def test_falls_back_when_the_address_has_no_local_part
    assert_equal 'user', login_for('@a.example')
    assert_equal 'user', login_for('')
  end

  def test_two_different_people_never_share_a_login
    first = login_for('john@a.example')
    taken_logins << first
    second = login_for('john@b.example')
    taken_logins << second
    third = login_for('john@c.example')

    assert_equal %w[john john@b.example john@c.example], [first, second, third]
  end
end
