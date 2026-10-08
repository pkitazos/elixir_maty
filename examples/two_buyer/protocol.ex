defmodule TwoBuyer.Protocol do
  use Maty.Protocol

  @projection {:buyer1,
               ~q"+seller:{title(binary).&seller:{quote(number).+buyer2:{share(number).end}}}"}

  @projection {:buyer2,
               ~q"&buyer1:{share(number).+seller:{address(binary).&seller:{date(date).end}, quit(nil).end}}"}

  @projection {:seller,
               ~q"&buyer1:{title(binary).+buyer1:{quote(number).&buyer2:{address(binary).+buyer2:{date(date).end},quit(nil).end}}}"}
end
