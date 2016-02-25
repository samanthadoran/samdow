import area, server, user, sets, sequtils, strutils
import asyncnet, asyncdispatch

var areaOne = newArea("Area One")
var areaTwo = newArea("Area Two")
var serveOne = newServer(area = areaOne, name = "Server One")
var serveTwo = newServer(area = areaTwo, name = "Server Two")
serveOne.exits.add(serveTwo)
serveTwo.exits.add(serveOne)

var serve = serveOne
asynccheck serveOne.serve(12345)
asynccheck serveTwo.serve(54321)

runForever()
