import Foundation

print("Hello from Swift!")

let semaphore = DispatchSemaphore(value: 0)

Task {
    print("In task")
    semaphore.signal()
}

print("Waiting...")
semaphore.wait()
print("Done!")