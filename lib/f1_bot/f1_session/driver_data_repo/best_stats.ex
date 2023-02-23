defmodule F1Bot.F1Session.DriverDataRepo.BestStats do
  @moduledoc """
  Processes and holds best-of session statistics, such as the overall fastest lap and top speed.
  """
  use TypedStruct

  alias F1Bot.F1Session.DriverDataRepo.Events

  alias F1Bot.F1Session.DriverDataRepo.DriverData.{
    EndOfLapResult,
    EndOfSectorResult
  }

  @type fastest_sectors :: %{
          1 => Timex.Duration.t() | nil,
          2 => Timex.Duration.t() | nil,
          3 => Timex.Duration.t() | nil
        }

  typedstruct do
    @typedoc "Session-wide stats for fastest laps, top speed across all drivers"

    field(:fastest_lap, Timex.Duration.t(), default: nil)
    field(:top_speed, non_neg_integer(), default: nil)
    field(:fastest_sectors, fastest_sectors(), default: %{1 => nil, 2 => nil, 3 => nil})
  end

  def new() do
    %__MODULE__{}
  end

  @doc """
  Tracks session-wide best lap and top speed stats, and creates events
  when a driver beats a session-wide or personal best record.
  """
  def push_end_of_lap_result(
        self = %__MODULE__{},
        eol_result = %EndOfLapResult{}
      ) do
    {self, lap_time_events} = evaluate_end_of_lap_time(self, eol_result)
    {self, speed_events} = evaluate_end_of_lap_speed(self, eol_result)

    events = lap_time_events ++ speed_events
    {self, events}
  end

  @doc """
  Tracks session-wide best sector times, and creates events
  when a driver beats a session-wide record.
  """
  def push_end_of_sector_result(
        self = %__MODULE__{fastest_sectors: fastest_sectors},
        eos_result = %EndOfSectorResult{}
      ) do
    curr_fastest_time = fastest_sectors[eos_result.sector]

    if curr_fastest_time == nil do
      fastest_sectors = Map.put(fastest_sectors, eos_result.sector, eos_result.sector_time)
      self = %{self | fastest_sectors: fastest_sectors}

      event =
        Events.make_agg_fastest_sector_event(
          eos_result.driver_number,
          :overall,
          eos_result.sector,
          eos_result.sector_time,
          nil
        )

      {self, List.wrap(event)}
    else
      overall_best_delta = Timex.Duration.diff(eos_result.sector_time, curr_fastest_time)
      overall_best_delta_ms = Timex.Duration.to_milliseconds(overall_best_delta)
      is_overall_record = overall_best_delta_ms < 0

      self =
        if is_overall_record do
          fastest_sectors = Map.put(fastest_sectors, eos_result.sector, eos_result.sector_time)
          %{self | fastest_sectors: fastest_sectors}
        else
          self
        end

      event =
        cond do
          is_overall_record ->
            Events.make_agg_fastest_sector_event(
              eos_result.driver_number,
              :overall,
              eos_result.sector,
              eos_result.sector_time,
              overall_best_delta
            )

          true ->
            nil
        end

      {self, List.wrap(event)}
    end
  end

  defp evaluate_end_of_lap_time(
         self = %__MODULE__{},
         _eol_result = %EndOfLapResult{lap_time: nil}
       ),
       do: {self, []}

  defp evaluate_end_of_lap_time(
         self = %__MODULE__{fastest_lap: fastest_lap},
         eol_result = %EndOfLapResult{}
       ) do
    if fastest_lap == nil do
      self = %{self | fastest_lap: eol_result.lap_time}

      events = [
        Events.make_agg_fastest_lap_event(
          eol_result.driver_number,
          :overall,
          eol_result.lap_time,
          nil
        )
      ]

      {self, events}
    else
      overall_best_delta = Timex.Duration.diff(eol_result.lap_time, fastest_lap)
      overall_best_delta_ms = Timex.Duration.to_milliseconds(overall_best_delta)
      is_overall_record = overall_best_delta_ms < 0

      self =
        if is_overall_record do
          %{self | fastest_lap: eol_result.lap_time}
        else
          self
        end

      record_event =
        cond do
          is_overall_record ->
            Events.make_agg_fastest_lap_event(
              eol_result.driver_number,
              :overall,
              eol_result.lap_time,
              overall_best_delta
            )

          eol_result.is_fastest_lap ->
            Events.make_agg_fastest_lap_event(
              eol_result.driver_number,
              :personal,
              eol_result.lap_time,
              eol_result.lap_delta
            )

          true ->
            nil
        end

      events = List.wrap(record_event)

      {self, events}
    end
  end

  defp evaluate_end_of_lap_speed(
         self = %__MODULE__{},
         _eol_result = %EndOfLapResult{lap_top_speed: nil}
       ),
       do: {self, []}

  defp evaluate_end_of_lap_speed(
         self = %__MODULE__{top_speed: top_speed},
         eol_result = %EndOfLapResult{}
       ) do
    if top_speed == nil do
      self = %{self | top_speed: eol_result.lap_top_speed}

      events = [
        Events.make_agg_top_speed_event(
          eol_result.driver_number,
          :overall,
          eol_result.lap_top_speed,
          nil
        )
      ]

      {self, events}
    else
      overall_speed_delta = eol_result.lap_top_speed - top_speed
      is_overall_record = overall_speed_delta > 0

      self =
        if is_overall_record do
          %{self | top_speed: eol_result.lap_top_speed}
        else
          self
        end

      record_event =
        cond do
          is_overall_record ->
            Events.make_agg_top_speed_event(
              eol_result.driver_number,
              :overall,
              eol_result.lap_top_speed,
              overall_speed_delta
            )

          eol_result.is_top_speed ->
            Events.make_agg_top_speed_event(
              eol_result.driver_number,
              :personal,
              eol_result.lap_top_speed,
              eol_result.speed_delta
            )

          true ->
            nil
        end

      events = List.wrap(record_event)
      {self, events}
    end
  end
end
