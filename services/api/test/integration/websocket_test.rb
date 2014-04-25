require 'test_helper'
require 'websocket_runner'
require 'oj'
require 'database_cleaner'

DatabaseCleaner.strategy = :truncation

class WebsocketTest < ActionDispatch::IntegrationTest
  self.use_transactional_fixtures = false

  setup do
    DatabaseCleaner.start
  end

  teardown do
    DatabaseCleaner.clean
  end

  def ws_helper (token = nil, timeout = true)
    opened = false
    close_status = nil
    too_long = false

    EM.run {
      if token
        ws = Faye::WebSocket::Client.new("ws://localhost:3002/websocket?api_token=#{api_client_authorizations(token).api_token}")
      else
        ws = Faye::WebSocket::Client.new("ws://localhost:3002/websocket")
      end

      ws.on :open do |event|
        opened = true
        if timeout
          EM::Timer.new 3 do
            too_long = true
            EM.stop_event_loop
          end
        end
      end

      ws.on :close do |event|
        close_status = [:close, event.code, event.reason]
        EM.stop_event_loop
      end

      yield ws
    }

    assert opened, "Should have opened web socket"
    assert (not too_long), "Test took too long"
    assert_equal 1000, close_status[1], "Connection closed unexpectedly (check log for errors)"
  end

  test "connect with no token" do
    status = nil

    ws_helper do |ws|
      ws.on :message do |event|
        d = Oj.load event.data
        status = d["status"]
        ws.close
      end
    end

    assert_equal 401, status
  end


  test "connect, subscribe and get response" do
    status = nil

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        status = d["status"]
        ws.close
      end
    end

    assert_equal 200, status
  end

  test "connect, subscribe, get event" do
    state = 1
    spec = nil
    ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          spec = Specimen.create
          state = 2
        when 2
          ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil spec
    assert_equal spec.uuid, ev_uuid
  end

  test "connect, subscribe, get two events" do
    state = 1
    spec = nil
    human = nil
    spec_ev_uuid = nil
    human_ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          spec = Specimen.create
          human = Human.create
          state = 2
        when 2
          spec_ev_uuid = d["object_uuid"]
          state = 3
        when 3
          human_ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil spec
    assert_not_nil human
    assert_equal spec.uuid, spec_ev_uuid
    assert_equal human.uuid, human_ev_uuid
  end

  test "connect, subscribe, filter events" do
    state = 1
    human = nil
    human_ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe', filters: [['object_uuid', 'is_a', 'arvados#human']]}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          Specimen.create
          human = Human.create
          state = 2
        when 2
          human_ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil human
    assert_equal human.uuid, human_ev_uuid
  end


  test "connect, subscribe, multiple filters" do
    state = 1
    spec = nil
    human = nil
    spec_ev_uuid = nil
    human_ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe', filters: [['object_uuid', 'is_a', 'arvados#human']]}.to_json)
        ws.send ({method: 'subscribe', filters: [['object_uuid', 'is_a', 'arvados#specimen']]}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          state = 2
        when 2
          assert_equal 200, d["status"]
          spec = Specimen.create
          human = Human.create
          state = 3
        when 3
          spec_ev_uuid = d["object_uuid"]
          state = 4
        when 4
          human_ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil spec
    assert_not_nil human
    assert_equal spec.uuid, spec_ev_uuid
    assert_equal human.uuid, human_ev_uuid
  end

  test "connect, subscribe, ask events starting at seq num" do
    state = 1
    human = nil
    human_ev_uuid = nil

    authorize_with :admin

    lastid = logs(:log3).id
    l1 = nil
    l2 = nil

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe', last_log_id: lastid}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          state = 2
        when 2
          l1 = d["object_uuid"]
          state = 3
        when 3
          l2 = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_equal l1, logs(:log4).object_uuid
    assert_equal l2, logs(:log5).object_uuid
  end

  test "connect, subscribe, get event, unsubscribe" do
    state = 1
    spec = nil
    spec_ev_uuid = nil
    filter_id = nil

    authorize_with :admin

    ws_helper :admin, false do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
        EM::Timer.new 3 do
          ws.close
        end
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          filter_id = d["filter_id"]
          spec = Specimen.create
          state = 2
        when 2
          spec_ev_uuid = d["object_uuid"]
          ws.send ({method: 'unsubscribe', filter_id: filter_id}.to_json)

          EM::Timer.new 1 do
            Human.create
          end

          state = 3
        when 3
          assert_equal 200, d["status"]
          state = 4
        when 4
          assert false, "Should not get any more events"
        end
      end

    end

    assert_not_nil spec
    assert_equal spec.uuid, spec_ev_uuid
  end


  test "connect, subscribe, get event, try to unsubscribe with bogus filter_id" do
    state = 1
    spec = nil
    spec_ev_uuid = nil
    human = nil
    human_ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          spec = Specimen.create
          state = 2
        when 2
          spec_ev_uuid = d["object_uuid"]
          ws.send ({method: 'unsubscribe', filter_id: 100000}.to_json)

          EM::Timer.new 1 do
            human = Human.create
          end

          state = 3
        when 3
          assert_equal 404, d["status"]
          state = 4
        when 4
          human_ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil spec
    assert_not_nil human
    assert_equal spec.uuid, spec_ev_uuid
    assert_equal human.uuid, human_ev_uuid
  end

  test "connect, subscribe, get event, try to unsubscribe with missing filter_id" do
    state = 1
    spec = nil
    spec_ev_uuid = nil
    human = nil
    human_ev_uuid = nil

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          spec = Specimen.create
          state = 2
        when 2
          spec_ev_uuid = d["object_uuid"]
          ws.send ({method: 'unsubscribe'}.to_json)

          EM::Timer.new 1 do
            human = Human.create
          end

          state = 3
        when 3
          assert_equal 400, d["status"]
          state = 4
        when 4
          human_ev_uuid = d["object_uuid"]
          ws.close
        end
      end

    end

    assert_not_nil spec
    assert_not_nil human
    assert_equal spec.uuid, spec_ev_uuid
    assert_equal human.uuid, human_ev_uuid
  end


  test "connected, not subscribed, no event" do
    authorize_with :admin

    ws_helper :admin, false do |ws|
      ws.on :open do |event|
        EM::Timer.new 1 do
          Specimen.create
        end

        EM::Timer.new 3 do
          ws.close
        end
      end

      ws.on :message do |event|
        assert false, "Should not get any messages, message was #{event.data}"
      end
    end
  end

  test "connected, not authorized to see event" do
    state = 1

    authorize_with :admin

    ws_helper :active, false do |ws|
      ws.on :open do |event|
        ws.send ({method: 'subscribe'}.to_json)

        EM::Timer.new 3 do
          ws.close
        end
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when 1
          assert_equal 200, d["status"]
          Specimen.create
          state = 2
        when 2
          assert false, "Should not get any messages, message was #{event.data}"
        end
      end

    end

  end

  test "connect, try bogus method" do
    status = nil

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({method: 'frobnabble'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        status = d["status"]
        ws.close
      end
    end

    assert_equal 400, status
  end

  test "connect, missing method" do
    status = nil

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send ({fizzbuzz: 'frobnabble'}.to_json)
      end

      ws.on :message do |event|
        d = Oj.load event.data
        status = d["status"]
        ws.close
      end
    end

    assert_equal 400, status
  end

  test "connect, send malformed request" do
    status = nil

    ws_helper :admin do |ws|
      ws.on :open do |event|
        ws.send '<XML4EVER></XML4EVER>'
      end

      ws.on :message do |event|
        d = Oj.load event.data
        status = d["status"]
        ws.close
      end
    end

    assert_equal 400, status
  end


  test "connect, try subscribe too many filters" do
    state = 1

    authorize_with :admin

    ws_helper :admin do |ws|
      ws.on :open do |event|
        (1..17).each do |i|
          ws.send ({method: 'subscribe', filters: [['object_uuid', '=', i]]}.to_json)
        end
      end

      ws.on :message do |event|
        d = Oj.load event.data
        case state
        when (1..16)
          assert_equal 200, d["status"]
          state += 1
        when 17
          assert_equal 403, d["status"]
          ws.close
        end
      end

    end

    assert_equal 17, state

  end

end
