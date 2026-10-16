import clsx from 'clsx'
import React from 'react'

interface Props {
  className?: string
  loading?: 'lazy' | 'eager'
  priority?: 'auto' | 'high' | 'low'
}

/** The wordmark: the one bold weight in the type scale (see .claude/c_c_design_type.md). */
export const Logo = (props: Props) => {
  const { className } = props
  return (
    <span
      className={clsx('font-bold text-[22px] leading-none tracking-[-0.01em] text-foreground', className)}
      aria-label="Colorgain"
    >
      Colorgain
    </span>
  )
}
