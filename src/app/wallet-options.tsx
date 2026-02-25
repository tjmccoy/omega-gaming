import * as React from 'react'
import { Connector, useConnect, useConnectors } from 'wagmi'

export function WalletOptions() {
  const { connect } = useConnect()
  const connectors = useConnectors()

  return connectors.map((connector) => (
    <button key={connector.uid} onClick={() => connect({ connector })}>
      {connector.name}
    </button>
  ))
}