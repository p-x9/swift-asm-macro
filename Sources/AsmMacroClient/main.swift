import AsmMacro

@Asm("""
let value = 40 + 2
return value
""")
func answer() -> Int

print("The generated answer is \(answer())")
