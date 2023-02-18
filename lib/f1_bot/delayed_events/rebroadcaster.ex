defmodule F1Bot.DelayedEvents.Rebroadcaster do
  use GenServer
  alias F1Bot.DelayedEvents
  alias F1Bot.Ets

  @ets_table_prefix :delayed_events

  def start_link(options) do
    delay_ms = Keyword.fetch!(options, :delay_ms)

    options = %{
      delay_ms: delay_ms
    }

    GenServer.start_link(__MODULE__, options, name: server_via(delay_ms))
  end

  def server_via(delay_ms) do
    :"#{__MODULE__}::#{delay_ms}"
  end

  def fetch_latest_event(delay_ms, event_scope, event_type) do
    delay_ms
    |> ets_table_name()
    |> Ets.fetch({atom(event_scope), atom(event_type)})
  end

  @impl true
  def init(options) do
    {:ok, timer_ref} = :timer.send_interval(100, :rebroadcast)

    options.delay_ms
    |> ets_table_name()
    |> Ets.new()

    state =
      options
      |> Map.put(:events, [])
      |> Map.put(:timer_ref, timer_ref)

    {:ok, state}
  end

  @impl true
  def handle_info(:rebroadcast, state) do
    delay_ms = state.delay_ms
    now = System.monotonic_time(:millisecond)

    until_ts = now - delay_ms
    state = rebroadcast_batch(state, until_ts)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        event = %{scope: _, type: _, payload: _},
        state
      ) do
    state = update_in(state.events, &(&1 ++ [event]))

    {:noreply, state}
  end

  defp rebroadcast_batch(%{events: []} = state, _until_ts), do: state

  defp rebroadcast_batch(%{events: [event | rest_events]} = state, until_ts) do
    if event.timestamp <= until_ts do
      save_latest_event(state, event)
      do_rebroadcast(state, event)

      state = %{state | events: rest_events}

      rebroadcast_batch(state, until_ts)
    else
      state
    end
  end

  defp do_rebroadcast(state, event) do
    topic = DelayedEvents.delayed_topic_for_event(event.scope, event.type, state.delay_ms)
    F1Bot.PubSub.broadcast(topic, event)
  end

  defp save_latest_event(state, event) do
    state.delay_ms
    |> ets_table_name()
    |> Ets.insert({atom(event.scope), atom(event.type)}, event)
  end

  defp ets_table_name(delay_ms), do: :"#{@ets_table_prefix}_#{delay_ms}"

  defp atom(x) when is_atom(x), do: x
  defp atom(x) when is_binary(x), do: String.to_atom(x)
end
