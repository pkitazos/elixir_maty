defmodule Mix.Tasks.StashQueue do
  use Mix.Task

  def run(_) do
    StashQueue.Main.start()
  end
end
