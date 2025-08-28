defmodule Store do
  @moduledoc """
  Data store abstraction for Redis key-value operations.
  Currently uses Agent for in-memory storage, but can be easily swapped
  for other storage backends.
  """

  @doc """
  Get a value by key from the store.
  Returns nil if the key doesn't exist.
  """
  def get(key) do
    Agent.get(:key_value_store, fn data -> data[key] end)
  end

  @doc """
  Put a value into the store with the given key.
  The value should be a map containing :value, :ttl, and :created_at.
  """
  def put(key, value) do
    Agent.update(:key_value_store, fn data -> Map.put(data, key, value) end)
  end

  @doc """
  Delete a key from the store.
  """
  def delete(key) do
    Agent.update(:key_value_store, fn data -> Map.delete(data, key) end)
  end

  @doc """
  Check if a key exists in the store.
  """
  def exists?(key) do
    Agent.get(:key_value_store, fn data -> Map.has_key?(data, key) end)
  end

  @doc """
  Get all keys in the store.
  """
  def keys do
    Agent.get(:key_value_store, fn data -> Map.keys(data) end)
  end

  @doc """
  Clear all data from the store.
  """
  def clear do
    Agent.update(:key_value_store, fn _ -> %{} end)
  end

  @doc """
  Get the total number of keys in the store.
  """
  def size do
    Agent.get(:key_value_store, fn data -> map_size(data) end)
  end

  @doc """
  Update a value in the store using a function.
  The function receives the current value and should return the new value.
  """
  def update(key, fun) do
    Agent.update(:key_value_store, fn data ->
      current_value = data[key]
      new_value = fun.(current_value)
      Map.put(data, key, new_value)
    end)
  end

  @doc """
  Get a value and update it atomically.
  Returns the old value and updates with the new value.
  """
  def get_and_update(key, fun) do
    Agent.get_and_update(:key_value_store, fn data ->
      current_value = data[key]
      {current_value, fun.(current_value)}
    end)
  end
end
