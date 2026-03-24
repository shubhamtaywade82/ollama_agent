---
name: ruby-design-patterns
description: All 23 GoF design patterns with Ruby implementations from refactoring.guru. Use when designing or refactoring Ruby/Rails code and you need to apply or recognize a design pattern. Covers Creational (5), Structural (7), and Behavioral (11) patterns with Ruby code examples and Rails-specific applications.
disable-model-invocation: true
---

# Ruby Design Patterns — Complete Reference

Source: https://refactoring.guru/design-patterns/ruby

> Don't force patterns. Let them emerge from refactoring. Apply when you recognize the problem, not speculatively.

## By Problem — Quick Lookup

| Problem | Pattern | Category |
|---|---|---|
| Creating families of compatible objects | Abstract Factory | Creational |
| Building complex objects step by step | Builder | Creational |
| Subclass decides which object to create | Factory Method | Creational |
| Clone objects without coupling to class | Prototype | Creational |
| One instance globally | Singleton | Creational |
| Incompatible interfaces must work together | Adapter | Structural |
| Split abstraction from implementation | Bridge | Structural |
| Tree structures, treat parts and wholes uniformly | Composite | Structural |
| Add behavior without subclassing | Decorator | Structural |
| Simplify a complex subsystem | Facade | Structural |
| Share common state across many objects | Flyweight | Structural |
| Control access to an object | Proxy | Structural |
| Pass request through a handler chain | Chain of Responsibility | Behavioral |
| Encapsulate a request as an object | Command | Behavioral |
| Traverse a collection without exposing it | Iterator | Behavioral |
| Decouple communicating objects | Mediator | Behavioral |
| Save and restore object state | Memento | Behavioral |
| Notify many objects about events | Observer | Behavioral |
| Alter behavior when state changes | State | Behavioral |
| Swap algorithms at runtime | Strategy | Behavioral |
| Define algorithm skeleton, defer steps | Template Method | Behavioral |
| Add operations without modifying classes | Visitor | Behavioral |

## Ruby-Native Pattern Support

| Pattern | Ruby built-in |
|---|---|
| Iterator | `Enumerable`, `Enumerator` |
| Observer | `Observable` module (stdlib) |
| Singleton | `Singleton` module (stdlib) |
| Decorator | Modules + `prepend` / `extend` |
| Strategy | Blocks / Procs / lambdas |
| Template Method | Inheritance + hook methods |
| Command | Proc / Method objects |

## Pattern Detail Files

- [Creational Patterns (1–5)](creational-patterns.md) — Abstract Factory, Builder, Factory Method, Prototype, Singleton
- [Structural Patterns (6–12)](structural-patterns.md) — Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy
- [Behavioral Patterns (13–22)](behavioral-patterns.md) — Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method, Visitor
