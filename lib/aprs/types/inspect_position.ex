defimpl Inspect, for: Aprs.Types.Position do
  alias Aprs.Types.Position

  def inspect(d, %{:structs => false} = opts) do
    Inspect.Algebra.to_doc(d, opts)
  end

  def inspect(d, _opts) do
    "#{Position.to_string(d)}"
  end
end
