import Foundation

print("Before async main")

@main
struct TestAsyncMain {
    static func main() async {
        print("Inside async main")
        print("Test completed")
    }
}

print("After struct definition")