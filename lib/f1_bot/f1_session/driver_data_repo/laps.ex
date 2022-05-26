defmodule F1Bot.F1Session.DriverDataRepo.Laps do
  @moduledoc """
  Stores all information about laps driven by a driver in the current session,
  e.g. lap number, lap time and timestamp.
  """
  use TypedStruct

  defmodule Lap do
    @moduledoc """
    Holds information about a single lap.
    """
    use TypedStruct

    typedstruct do
      @typedoc "Lap information"

      field(:number, pos_integer())
      field(:time, Timex.Duration.t())
      field(:timestamp, DateTime, enforce: true)
      # field(:tyre_compound, String.t())
      # field(:type, :normal | :inlap | :outlap, default: :normal)
    end
  end

  typedstruct do
    field(:data, [Lap.t()], default: [])
  end

  def new() do
    %__MODULE__{}
  end

  def find_by_close_timestamp(
        %__MODULE__{data: data},
        timestamp,
        max_deviation_ms
      ) do
    lap =
      data
      |> Enum.find(fn
        %{timestamp: ts} ->
          delta = Timex.diff(timestamp, ts, :milliseconds) |> abs()
          delta < max_deviation_ms
      end)

    if lap == nil do
      {:error, :not_found}
    else
      {:ok, lap}
    end
  end

  def fill_by_close_timestamp(
        self = %__MODULE__{data: data},
        args,
        timestamp,
        max_deviation_ms
      ) do
    {found, data_reversed} =
      Enum.reduce(data, {_skip = false, _new_data = []}, fn lap, {skip, data} ->
        cond do
          skip == true ->
            data = [lap | data]
            {skip, data}

          is_timestamp_in_range(lap.timestamp, timestamp, max_deviation_ms) ->
            lap = fill_lap_with_args(lap, args)
            data = [lap | data]
            {true, data}

          true ->
            data = [lap | data]
            {false, data}
        end
      end)

    if found do
      %{self | data: Enum.reverse(data_reversed)}
    else
      args = Keyword.put_new(args, :timestamp, timestamp)
      lap = create_lap_from_args(args)
      %{self | data: [lap | data]}
    end
  end

  defp fill_lap_with_args(lap, args) do
    old_args = Map.from_struct(lap)
    new_args = args |> Enum.into(%{})

    # Do not replace existing fields
    args =
      Map.merge(new_args, old_args, fn _key, new, old ->
        if old == nil do
          new
        else
          old
        end
      end)

    struct!(Lap, args)
  end

  def create_lap_from_args(args) do
    struct(Lap, args)
  end

  defp is_timestamp_in_range(ts1, ts2, max_ms) do
    delta = Timex.diff(ts1, ts2, :milliseconds) |> abs()

    delta < max_ms
  end
end