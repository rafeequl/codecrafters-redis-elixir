# Elixir Debugging Guide

## 1. **IEx.pry() - Interactive Breakpoint (Like Ruby's `binding.pry`)**

```elixir
# Add this to your code where you want to pause execution
require IEx; IEx.pry()
```

**How to use:**
1. Add `require IEx; IEx.pry()` to your code
2. Run with `iex -S mix` (not `mix run`)
3. When the code hits the pry, you'll get an interactive shell
4. You can inspect variables, run code, etc.
5. Type `respawn` to continue execution

**Example:**
```elixir
def handle_call({:xadd, stream_key, id, field_value_pairs}, _from, state) do
  existing_stream = Map.get(state.streams, stream_key, [])
  
  # Breakpoint here - like Ruby's binding.pry
  require IEx; IEx.pry()
  
  # Your code continues here...
end
```

## 2. **IO.inspect() - Better than Logger.debug**

```elixir
# Shows output in terminal immediately
IO.inspect({:debug, variable1, variable2}, label: "Debug Label")
```

**Why it's better than Logger.debug:**
- Shows immediately in terminal
- No need to configure log levels
- Always visible
- Can inspect complex data structures

## 3. **Running with Debugging**

### For IEx.pry():
```bash
iex -S mix
```

### For IO.inspect():
```bash
mix run your_script.exs
# or
mix test
```

## 4. **Debugging Your Current Issue**

Looking at your output, the problem is in the ID validation logic. The issue is:

1. **First XADD with "1-1"** - Should work for new stream, but fails
2. **All subsequent XADD calls** - Fail with same error

**The bug is likely in:**
- `validate_id_greater_than_existing_id/2` function
- String comparison logic (`id > latest_id`)

## 5. **Quick Fix for Your Current Bug**

The issue is that you're comparing strings lexicographically, but Redis IDs should be compared numerically.

**Current problematic code:**
```elixir
case id > latest_id do  # This is string comparison!
```

**Should be:**
```elixir
case compare_ids(id, latest_id) do
  :gt -> {:ok, id}
  _ -> {:error, "ERR The ID specified in XADD is equal or smaller than the target stream top item"}
end

defp compare_ids(id1, id2) do
  [ts1, seq1] = String.split(id1, "-")
  [ts2, seq2] = String.split(id2, "-")
  
  case {String.to_integer(ts1), String.to_integer(seq1)} do
    {t1, s1} when t1 > String.to_integer(ts2) -> :gt
    {t1, s1} when t1 == String.to_integer(ts2) and s1 > String.to_integer(seq2) -> :gt
    _ -> :lte
  end
end
```

## 6. **Other Debugging Techniques**

### **Process.info/1** - Inspect running processes
```elixir
Process.info(self())
Process.info(pid_of_your_genserver)
```

### **Observer** - Visual process monitoring
```elixir
:observer.start()
```

### **dbg/1** - Trace function calls
```elixir
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tp(YourModule, :your_function, :x)
```

### **ExUnit with debugging**
```elixir
test "debug test" do
  # Your test code
  IO.inspect(some_variable, label: "Debug")
  assert some_condition
end
```

## 7. **Common Debugging Patterns**

### **Debugging GenServer state:**
```elixir
def handle_call(:debug_state, _from, state) do
  IO.inspect(state, label: "Current State")
  {:reply, :ok, state}
end
```

### **Debugging with pattern matching:**
```elixir
def some_function(data) do
  case data do
    {:ok, result} -> 
      IO.inspect(result, label: "Success")
      result
    {:error, reason} -> 
      IO.inspect(reason, label: "Error")
      {:error, reason}
  end
end
```

### **Debugging with pipes:**
```elixir
data
|> IO.inspect(label: "Before processing")
|> process_data()
|> IO.inspect(label: "After processing")
```

## 8. **Removing Debug Code**

When you're done debugging, remove or comment out:
- `require IEx; IEx.pry()`
- `IO.inspect()` statements
- Or wrap them in `if Mix.env() == :dev do` blocks
