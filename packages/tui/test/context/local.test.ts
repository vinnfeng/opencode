import { expect, test } from "bun:test"
import { parseModel, recentModels, sessionModelToRestore, startupModel } from "../../src/context/local"

test("parses model IDs containing slashes", () => {
  expect(parseModel("provider/family/model")).toEqual({
    providerID: "provider",
    modelID: "family/model",
  })
})

test("moves a model to the front, deduplicates, and limits recents", () => {
  const recent = Array.from({ length: 12 }, (_, index) => ({
    providerID: "provider",
    modelID: `model-${index}`,
  }))

  expect(recentModels({ providerID: "provider", modelID: "model-5" }, recent)).toEqual([
    { providerID: "provider", modelID: "model-5" },
    ...recent.slice(0, 5),
    ...recent.slice(6, 10),
  ])
})

test("waits for providers before applying an explicit startup model", () => {
  const model = "provider/model"
  const isValid = (value: { providerID: string; modelID: string }) =>
    value.providerID === "provider" && value.modelID === "model"

  expect(startupModel(model, false, isValid)).toBeUndefined()
  expect(startupModel(model, true, isValid)).toEqual({
    providerID: "provider",
    modelID: "model",
  })
})

test("does not let a resumed session replace an explicit startup model", () => {
  const previous = { providerID: "previous", modelID: "session-model", variant: "low" }

  expect(sessionModelToRestore(undefined, previous)).toEqual(previous)
  expect(sessionModelToRestore("provider/start-model", previous)).toBeUndefined()
})
