defmodule F1Bot.ExternalApi.Discord.Commands.Summary do
  @moduledoc """
  Handles Discord command for displaying driver's session summary
  """
  require Logger
  alias Nostrum.Struct.Interaction
  alias F1Bot
  alias F1Bot.F1Session.DriverDataRepo.DriverData.Summary
  alias F1Bot.F1Session.DriverCache.DriverInfo
  alias F1Bot.ExternalApi.Discord
  alias F1Bot.ExternalApi.Discord.Commands.{Response, OptionValidator}

  @behaviour Discord.Commands

  @impl Discord.Commands
  def handle_interaction(interaction = %Interaction{}, internal_args) do
    flags = Map.get(internal_args, :flags, [])

    case parse_interaction_options(interaction) do
      {:ok, parsed_opts} ->
        flags
        |> Response.make_deferred_message()
        |> Response.send_interaction_response(interaction)

        do_create_summary(interaction, parsed_opts, internal_args)

      {:error, option_error} ->
        flags
        |> Response.make_message("Error: #{option_error}")
        |> Response.send_interaction_response(interaction)
    end
  end

  # Silence Dialyzer warnings for bad &Api.create_followup_message/2 types
  @dialyzer {:no_fail_call, do_create_summary: 3}
  @dialyzer {:no_return, do_create_summary: 3}
  defp do_create_summary(interaction, options, internal_args) do
    flags = Map.get(internal_args, :flags, [])

    {:ok, session_info} = F1Bot.session_info()
    {:ok, driver_info} = F1Bot.driver_info_by_number(options.driver)
    {:ok, driver_data} = F1Bot.driver_session_data(options.driver)

    summary = Summary.generate(driver_data)

    embed = generate_summary_embed(session_info, driver_info, summary)

    flags
    |> Response.make_followup_message(nil, [], [embed])
    |> Response.send_followup_response(interaction)
  end

  defp generate_summary_embed(session_info, driver_info, summary) do
    %{
      type: "rich",
      color: DriverInfo.team_color_int(driver_info),
      title: driver_info.full_name,
      description: "#{session_info.gp_name} - #{session_info.type}",
      thumbnail: %{
        url: driver_info.picture_url
      },
      fields:
        [
          %{inline: true, name: "Fastest lap", value: format_lap_time(summary.fastest_lap)},
          %{inline: true, name: "Top speed", value: format_speed(summary.top_speed)},
          %{inline: true, name: "Stints", value: "#{length(summary.stints)}"}
        ] ++ generate_stint_fields(summary),
      footer: %{
        text: "Number in parentheses - tyre age when fitted (laps)"
      }
    }
  end

  defp generate_stint_fields(summary) do
    for stint <- summary.stints do
      tyre_emoji =
        "#{stint.compound}_tyre"
        |> String.to_atom()
        |> Discord.get_emoji()

      stint_info = "Stint #{stint.number + 1}"
      laps_info = "Lap #{stint.lap_start}-#{stint.lap_end}" |> format_width(9)
      timed_laps_info = "Timed laps: #{stint.timed_laps}" |> format_width(15)
      age_info = "(#{stint.tyre_age || 0})"

      first_row = "#{tyre_emoji}`#{age_info} #{stint_info}  #{laps_info}   #{timed_laps_info}`"

      avg_lap = format_lap_time(stint.average_time) |> format_width(8)
      fast_lap = format_lap_time(stint.fastest_time) |> format_width(8)

      second_row = "`Lap (min/avg):  #{fast_lap} /  #{avg_lap} `"

      %{
        inline: false,
        name: first_row,
        value: second_row
      }
    end
  end

  defp format_width(text, width), do: String.pad_trailing(text, width)

  defp format_lap_time(_time = nil), do: "N/A"

  defp format_lap_time(time = %Timex.Duration{}),
    do: F1Bot.DataTransform.Format.format_lap_time(time)

  defp format_speed(_speed = nil), do: "N/A"

  defp format_speed(speed), do: "#{speed} km/h"

  defp parse_interaction_options(interaction = %Interaction{}) do
    %Interaction{
      data: %{
        options: options
      }
    } = interaction

    with {:ok, driver_number} <- OptionValidator.validate_driver(options, "driver") do
      opts = %{
        driver: driver_number
      }

      {:ok, opts}
    end
  end
end