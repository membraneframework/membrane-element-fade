defmodule Membrane.Element.Fade.MultiplicativeFader do
  alias Membrane.Caps.Audio.Raw

  def fade(
        <<>>,
        _frames_left,
        _step,
        _to_level,
        _tanh_arg_range,
        _current_static_volume,
        _caps,
        state
      ),
      do: {<<>>, state}

  def fade(data, frames_left, step, to_level, tanh_arg_range, current_static_volume, caps, state) do
    state = state || %{tanh_arg: -tanh_arg_range}
    tanh_arg_delta = (tanh_arg_range - state.tanh_arg) * step / frames_left

    volume_gen = fn tanh_arg ->
      tanh_normalized(tanh_arg, tanh_arg_range, current_static_volume, to_level)
    end

    step_size = step * Raw.frame_size(caps)

    {data, tanh_arg} =
      data
      |> do_fade(step_size, caps, state.tanh_arg, tanh_arg_delta, volume_gen, <<>>)

    {data, %{state | tanh_arg: tanh_arg}}
  end

  defp do_fade(<<>>, _step_size, _caps, tanh_arg, _tanh_arg_delta, _volume_gen, acc),
    do: {acc, tanh_arg}

  defp do_fade(data, step_size, caps, tanh_arg, tanh_arg_delta, volume_gen, acc) do
    <<chunk::binary-size(step_size), rest::binary>> = data
    volume = volume_gen.(tanh_arg)
    chunk = chunk |> set_volume(volume, caps)

    rest
    |> do_fade(
      step_size,
      caps,
      tanh_arg + tanh_arg_delta,
      tanh_arg_delta,
      volume_gen,
      acc <> chunk
    )
  end

  def revolume(data, caps, level), do: data |> set_volume(level, caps)

  defp get_volume_level(x), do: (:math.exp(x) - 1) / (e() - 1)

  # base of the natural logarithm
  defp e(), do: :math.exp(1)

  defp tanh(x) do
    exp = :math.exp(-2 * x)
    (1 - exp) / (1 + exp)
  end

  defp tanh_normalized(x, range, old, new),
    do: (tanh(x) + range) / (2 * range) * (new - old) + old

  defp set_volume(data, 1, _caps), do: data

  defp set_volume(data, volume, caps) do
    sample_size = caps |> Raw.sample_size()
    volume_level = get_volume_level(volume)
    data |> do_set_volume(sample_size, caps, volume_level, <<>>)
  end

  defp do_set_volume(<<>>, _sample_size, _caps, _volume_level, acc), do: acc

  defp do_set_volume(data, sample_size, caps, volume_level, acc) do
    <<sample::binary-size(sample_size), rest::binary>> = data

    sample =
      sample
      |> Raw.sample_to_value(caps)
      |> Kernel.*(volume_level)
      |> round
      |> Raw.value_to_sample(caps)

    rest |> do_set_volume(sample_size, caps, volume_level, acc <> sample)
  end
end
