This is a translations system organized in a monorepo:

- gem: This contains the ruby gem (an engine) intended to be added to other ruby on rails projects to automatically manage the translations of that project. This gem automatically talks with the saas in production to translate things, download content, etc.
- dummy: This is only a dummy rails app used for testing and development purposes. It simulates a real ruby on rails application that uses the gem.
