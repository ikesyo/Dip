//
// Dip
//
// Copyright (c) 2015 Olivier Halligon <olivier@halligon.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import XCTest
@testable import Dip

private protocol Server: class {
  var client: Client? { get set }
}

private protocol Client: class {
  var server: Server { get }
}

private class ClientImp: Client, Equatable {
  var server: Server
  init(server: Server) {
    self.server = server
  }
}

private func ==<T: ClientImp>(lhs: T, rhs: T) -> Bool {
  return lhs === rhs
}

private class ServerImp: Server, Hashable {
  weak var client: Client?
  init() {}
  
  var hashValue: Int {
    return unsafeAddress(of: self).hashValue
  }
}

private func ==<T: ServerImp>(lhs: T, rhs: T) -> Bool {
  return lhs === rhs
}

private var resolvedServers = Set<ServerImp>()
private var resolvedClients = Array<ClientImp>()

private var container: DependencyContainer!

#if os(Linux)
import Glibc
private var lock: pthread_spinlock_t = 0

private let resolveClientSync: () -> Client? = {
  var clientPointer: UnsafeMutablePointer<Void>? = UnsafeMutablePointer<Void>(allocatingCapacity: 1)
  clientPointer = dispatch_sync { _ in
    let resolved = try! container.resolve() as Client
    let unmanaged = Unmanaged.passUnretained(resolved as! ClientImp)
    return UnsafeMutablePointer<Void>(OpaquePointer(bitPattern: Unmanaged.passUnretained(resolved as! ClientImp)))
  }
  return Unmanaged<ClientImp>.fromOpaque(OpaquePointer(clientPointer!)).takeUnretainedValue()
}
  
#else
let queue = NSOperationQueue()
let lock = NSRecursiveLock()
  
private let resolveClientSync: () -> Client? = {
  var client: Client?
  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
    client = try! container.resolve() as Client
  }
  return client
}
  
#endif

let resolveServerAsync = {
  let service = try! container.resolve() as Server
  lock.lock()
  resolvedServers.insert(service as! ServerImp)
  lock.unlock()
}

let resolveClientAsync = {
  let client = try! container.resolve() as Client
  lock.lock()
  resolvedClients.append(client as! ClientImp)
  lock.unlock()
}

class ThreadSafetyTests: XCTestCase {
  
  #if os(Linux)
  required init(name: String, testClosure: XCTestCase throws -> Void) {
    super.init(name: name, testClosure: testClosure)
    pthread_spin_init(&lock, 0)
  }
  
  static var allTests: [(String, ThreadSafetyTests -> () throws -> Void)] {
    return [
      ("testSingletonThreadSafety", testSingletonThreadSafety),
      ("testFactoryThreadSafety", testFactoryThreadSafety),
      ("testCircularReferenceThreadSafety", testCircularReferenceThreadSafety)
    ]
  }
  
  override func setUp() {
    container = DependencyContainer()
  }
  
  override class func tearDown() {
    resolvedServers.removeAll()
    resolvedClients.removeAll()
  }
  #else
  override func setUp() {
    container = DependencyContainer()
  }
  
  override func tearDown() {
    resolvedServers.removeAll()
    resolvedClients.removeAll()
  }
  #endif
  
  func testSingletonThreadSafety() {
    container.register(scope: .Singleton) { ServerImp() as Server }
    
    for _ in 0..<100 {
      #if os(Linux)
      dispatch_async({ _ in
        resolveServerAsync()
        return nil
      })
      #else
      queue.addOperation(resolveServerAsync)
      #endif
    }
    
    #if os(Linux)
    sleep(1)
    #else
    queue.waitUntilAllOperationsAreFinished()
    #endif
    
    XCTAssertEqual(resolvedServers.count, 1, "Should create only one instance")
  }
  
  
  func testFactoryThreadSafety() {
    container.register { ServerImp() as Server }
    
    for _ in 0..<100 {
      #if os(Linux)
      dispatch_async({ _ in
        resolveServerAsync()
        return nil
      })
      #else
      queue.addOperation(resolveServerAsync)
      #endif
    }
    
    #if os(Linux)
    sleep(1)
    #else
    queue.waitUntilAllOperationsAreFinished()
    #endif

    XCTAssertEqual(resolvedServers.count, 100, "All instances should be different")
  }
  
  
  func testCircularReferenceThreadSafety() {
    container.register(scope: .ObjectGraph) {
      ClientImp(server: try container.resolve()) as Client
    }
    
    container.register(scope: .ObjectGraph) { ServerImp() as Server }
      .resolveDependencies { container, server in
        server.client = resolveClientSync()
    }
    
    for _ in 0..<100 {
      #if os(Linux)
      dispatch_async({ _ in
        resolveClientAsync()
        return nil
      })
      #else
      queue.addOperation(resolveClientAsync)
      #endif
    }
    
    #if os(Linux)
    sleep(1)
    #else
    queue.waitUntilAllOperationsAreFinished()
    #endif
    
    XCTAssertEqual(resolvedClients.count, 100, "Instances should be not reused in different object graphs")
    for client in resolvedClients {
      let service = client.server as! ServerImp
      let serviceClient = service.client as! ClientImp
      XCTAssertEqual(serviceClient, client, "Instances should be reused when resolving single object graph")
    }
  }
  
}


