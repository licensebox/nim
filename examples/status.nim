import std/json
import licensebox
proc main() =
  let c = newClient(%*{"product":"your-product", "keys":{"current":"YOUR_PUBLIC_KEY"}})
  defer: c.close()
  try: echo c.requireModule("core")
  except LicenseboxError as e: stderr.writeLine(e.code & ": " & e.msg)
main()
