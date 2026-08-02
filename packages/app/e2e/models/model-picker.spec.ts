import { test, expect } from "../fixtures"
import { promptSelector } from "../selectors"
import { clickListItem } from "../actions"

test("smoke model selection updates prompt footer", async ({ page, gotoSession }) => {
  await gotoSession()

  await page.locator(promptSelector).click()
  await page.keyboard.type("/model")

  const command = page.locator('[data-slash-id="model.choose"]')
  await expect(command).toBeVisible()
  await command.hover()

  await page.keyboard.press("Enter")

  const dialog = page.getByRole("dialog")
  await expect(dialog).toBeVisible()

  const input = dialog.getByRole("textbox").first()

  // The configured model can disappear from a dynamic provider catalog. The
  // picker should still let the user choose any available model in that case.
  const items = dialog.locator('[data-slot="list-item"][data-key]')
  const other = dialog.locator('[data-slot="list-item"][data-key]:not([data-selected="true"])').first()
  const target = (await other.count()) > 0 ? other : items.first()
  await expect(target).toBeVisible()

  const key = await target.getAttribute("data-key")
  if (!key) throw new Error("Failed to resolve model key from list item")

  const model = key.split(":").slice(1).join(":")

  await input.fill(model)

  await clickListItem(dialog, { key })

  await expect(dialog).toHaveCount(0)

  await page.locator(promptSelector).click()
  await page.keyboard.type("/model")
  await expect(command).toBeVisible()
  await command.hover()
  await page.keyboard.press("Enter")

  const dialogAgain = page.getByRole("dialog")
  await expect(dialogAgain).toBeVisible()
  await expect(dialogAgain.locator(`[data-slot="list-item"][data-key="${key}"][data-selected="true"]`)).toBeVisible()
})
