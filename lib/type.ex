defmodule PropCheck.Type do
	@moduledoc """
	This modules defines the syntax tree of types and translates the type definitions
	of Elixir into the internal format. It also provides functions for analysis of types. 
	"""

	@type env :: %{mfa: __MODULE__.t}
	@type kind_t :: :type | :opaque | :typep | :none

	@predefined_types [:atom, :integer, :pos_number, :neg_number, :non_neg_number, :boolean, :byte, 
		:char, :number, :char_list, :any, :term, :io_list, :io_data, :module, :mfa, :arity, :port,
		:node, :timeout, :node, :fun, :binary, :bitstring]

	defstruct name: :none,
		params: [],
		kind: :none,
		expr: nil,
		uses: []

	@type t :: %__MODULE__{name: atom, params: [atom], kind: kind_t, 
		expr: Macro.t, uses: [atom | mfa]}

	defmodule TypeExpr do
		@typedoc """
		Various type constructors, `:ref` denote a reference to an existing type or 
		parameter, `:literal` means a literal value, in many cases, this will be an atom value.
		"""	
		@type constructor_t :: :union | :tuple | :list | :map | :ref | :literal | :var | :none
		defstruct constructor: :none,
			args: [] # elements of union, tuple, list or map; or the referenced type or the literal value
	
		defimpl Inspect, for: __MODULE__ do
			import Inspect.Algebra

			def inspect(%{constructor: c, args: a}, opts) do
				surround_many("%#{TypeExpr}{", 
					[constructor: c, args: a],
					"}",
					%Inspect.Opts{limit: :infinity},
					fn {f, v}, o -> group glue(concat(Atom.to_string(f), ":"), to_doc(v, opts)) end
				)
			end
		end
	end


	@doc "Takes a type specification as an Elixir AST and returns the type def."
	@spec parse_type({kind_t, Macro.t, nil, any}) :: t
	def parse_type({kind, {:::, _, [header, body] = typedef}, nil, _env}) 
	when kind in [:type, :opaque, :typep] do
		{name, _, ps} = header
		params = case ps do
			nil -> []
			l -> l |> Enum.map fn({n, _, _}) -> n end
		end
		%__MODULE__{name: name, params: params, kind: kind, expr: parse_body(body, params)}
	end
	
	def parse_body({:|, _, children}, params) do
		args = children |> Enum.map fn(child) -> parse_body(child, params) end
		%TypeExpr{constructor: :union, args: args}
	end
	def parse_body({:{}, _, children}, params) do
		args = children |> Enum.map fn(child) -> parse_body(child, params) end
		%TypeExpr{constructor: :tuple, args: args}
	end
	def parse_body({type, _, nil}, _params) when type in @predefined_types do
		%TypeExpr{constructor: :ref, args: [type]}
	end
	def parse_body({var, _, nil}, params) when is_atom(var) do
		true = params |> Enum.member? var
		%TypeExpr{constructor: :var, args: [var]}
	end
	def parse_body({type, _, sub}, params) when is_atom(type) do
		ps = sub |> Enum.map fn s -> parse_body s, params end
		%TypeExpr{constructor: :ref, args: [type, ps]}
	end
	def parse_body(body, _params) when not(is_tuple(body)) do
		%TypeExpr{constructor: :literal, args: [body]}
	end
	

	@doc "Calculates the list of referenced types"
	def referenced_types({type_gen, _, l}, params) 
	when is_list(l) and type_gen in [:.., :{}, :list] do 
		l |> Enum.map(&(referenced_types(&1, params))) |> List.flatten
	end
	def referenced_types({:list, _, nil}, params) do [] end
	def referenced_types(body, params) do
		[]
	end	

end