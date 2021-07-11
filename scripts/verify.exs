defmodule Verifier do
  def verify(path) do
    code = File.read!(path)
    IO.puts(path)
    {:ok, ast} = Code.string_to_quoted(code, file: path, columns: true)
    # IO.inspect(ast)

    tree_sitter_path = Path.expand("../node_modules/.bin/tree-sitter", __DIR__)
    {ts_sexp, 0} = System.cmd(tree_sitter_path, ["parse", Path.expand(path)])
    ts_sexp = scrub(ts_sexp)

    elixir_sexp =
      to_sexp(ast)
      |> then(&{:program, [], [&1]})
      |> format()

    if ts_sexp != elixir_sexp do
      File.write!("/tmp/ts_sexp", ts_sexp)
      File.write!("/tmp/elixir_sexp", elixir_sexp)
      System.cmd("icdiff", ["/tmp/ts_sexp", "/tmp/elixir_sexp"], into: IO.stream())
    end
  end

  defp scrub(ts_sexp) do
    ts_sexp
    |> String.replace(~r/ \[\d+, \d+\] - \[\d+, \d+\]/, "")
    |> String.replace(~r/\w+: /, "")
  end

  defp format({name, _m, []}) do
    "(" <> to_string(name) <> ")"
  end

  defp format({name, _m, children}) do
    body =
      Enum.map(children, &format/1)
      |> Enum.join("\n")
      |> indent()

    "(" <> to_string(name) <> "\n" <> body <> ")"
  end

  defp to_sexp({:__aliases__, _m, _args}) do
    {:module, [], []}
  end

  defp to_sexp({{:., _m, [left, right]}, _m, arguments}) do
    {:dot_call, [],
     [
       to_sexp(left),
       {:function_identifier, [], []},
       {:arguments, [], Enum.map(arguments, &to_sexp/1)}
     ]}
  end

  defp to_sexp([{:do, {:__block__, _m, args}}]) do
    {:do_block, [], Enum.map(args, &to_sexp/1)}
  end

  defp to_sexp([{:do, ast}]) do
    {:do_block, [], [to_sexp(ast)]}
  end

  defp to_sexp({key, value}) when is_atom(key) do
    {:keyword, [], [to_sexp(value)]}
  end

  defp to_sexp(false) do
    {false, [], []}
  end

  defp to_sexp(ast) when is_atom(ast) do
    {:atom, [], [{:atom_literal, [], []}]}
  end

  defp to_sexp(ast) when is_list(ast) do
    if Keyword.keyword?(ast) do
      {:list, [],
       [
         {:keyword_list, [],
          Enum.flat_map(ast, fn {key, value} ->
            [{:keyword, [], [{:keyword_literal, [], []}]}, to_sexp(value)]
          end)}
       ]}
    else
      {:list, [], Enum.map(ast, &to_sexp/1)}
    end
  end

  defp to_sexp({_, _m, nil}) do
    {:identifier, [], []}
  end

  defp to_sexp({_, _m, args} = ast) do
    children = Enum.map(args, &to_sexp/1)
    {:call, [], [{:function_identifier, [field: "function"], []} | children]}
  end

  defp to_sexp(unknown) do
    IO.inspect(unknown)
    unknown
  end

  defp indent(string) do
    String.split(string, "\n")
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
  end
end

# globs = ["../../elixir/**/*.ex*"]
globs = ["../elixir/lib/eex/**/*.exs"]
File.cd!(Path.join(__DIR__, ".."))

for glob <- globs do
  for path <- Path.wildcard(glob) do
    Verifier.verify(path)
  end
end
