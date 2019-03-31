defimpl Inspect, for: Aprs.Types.Position do
  alias Aprs.Types.Position

  @spec inspect(any(), any()) ::
          :doc_line
          | :doc_nil
          | binary()
          | {:doc_collapse, pos_integer()}
          | {:doc_force, any()}
          | {:doc_break | :doc_color | :doc_cons | :doc_fits | :doc_group | :doc_string, any(),
             any()}
          | {:doc_nest, any(), :cursor | :reset | non_neg_integer(), :always | :break}
  def inspect(d, %{:structs => false} = opts) do
    Inspect.Algebra.to_doc(d, opts)
  end

  def inspect(d, _opts) do
    "#{Position.to_string(d)}"
  end
end
