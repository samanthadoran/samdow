
type
  Area* = ref AreaObj
  AreaObj = object
    name*: string


proc newArea*(name: string): Area =
  new(result)
  result.name = name
