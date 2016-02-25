import area, server, user, sets, sequtils, strutils
import asyncnet, asyncdispatch

proc printMessages(s: AsyncSocket) {.async.} =
  while true:
    let line = await s.recvLine()
    echo(line)

proc sendMessages(s: AsyncSocket) {.async.} =
  while true:
    echo("Enter a message...")
    let msg = stdin.readLine().strip() & "\r\L"
    await s.send(msg)

proc main() {.async.} =
  var s = newAsyncSocket()
  await s.connect("127.0.0.1", Port(12345))

  echo("Enter a nickname")
  let nick = stdin.readLine().strip() & "\r\L"
  await s.send(nick)

  asyncCheck s.printMessages()
  asyncCheck s.sendMessages()
  discard """
  while true:
    echo("Enter a message...")
    let msg = stdin.readLine().strip() & "\r\L"
    waitfor s.send(msg)
  """

asyncCheck main()
runForever()
