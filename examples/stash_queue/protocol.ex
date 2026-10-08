defmodule StashQueue.Protocol do
  use Maty.Protocol

  @projection {:p, ~q/+q:{a(number).+q:{a(number).end}}/}
  @projection {:q, ~q/&p:{a(number).&r:{b(number).&r:{b(number).&p:{a(number).end}}}}/}
  @projection {:r, ~q/+q:{b(number).+q:{b(number).end}}/}
end
