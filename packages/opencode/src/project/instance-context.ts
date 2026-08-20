import { LocalContext } from "@/util/local-context"
import { FSUtil } from "@opencode-ai/core/fs-util"
import path from "path"
import type * as Project from "./project"

export interface InstanceContext {
  directory: string
  worktree: string
  project: Project.Info
}

export const context = LocalContext.create<InstanceContext>("instance")

/**
 * Check if a path is within the project boundary.
 * Returns true if path is inside ctx.directory OR ctx.worktree.
 * Paths within the worktree but outside the working directory should not trigger external_directory permission.
 */
export function containsPath(filepath: string, ctx: InstanceContext): boolean {
  if (FSUtil.contains(ctx.directory, filepath)) return true
  // Non-git projects use the filesystem root as worktree, which would match
  // every absolute path. Account for both POSIX "/" and Windows drive roots.
  const worktree = path.resolve(ctx.worktree)
  if (worktree === path.parse(worktree).root) return false
  return FSUtil.contains(ctx.worktree, filepath)
}
