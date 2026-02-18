'use client'

import { useConnect, useConnection, useConnectors, useDisconnect } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { WagmiProvider } from 'wagmi'
import { config } from '../../config'
import { Connection } from './connection'
import { WalletOptions } from './wallet-options'


const queryClient = new QueryClient()


function ConnectWallet() {
  const { isConnected } = useConnection()
  if (isConnected) return <Connection />
  return <WalletOptions />
}

function App() {
  const connection = useConnection()
  const { connect, status, error } = useConnect()
  const connectors = useConnectors()
  const { disconnect } = useDisconnect()

  return (
<>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>

      <h1 className='title'>Omega Gaming</h1>
        <div>
          status: {connection.status}
          <br />
          addresses: {JSON.stringify(connection.addresses)}
          <br />
          chainId: {connection.chainId}
        </div>
      <div>
        <h2>A Trustless Lottery</h2>

        <div className='connect-wallet-container'>
            <ConnectWallet />
        </div>

        <div className='squares-container'> 
          <div className='square'> Active Players </div>
          <div className='square'> Prize Pool </div>
          <div className='square'> Time Remaining </div>
        </div>

        

      </div>
        </QueryClientProvider>
        </WagmiProvider>
  </>
  )
}

export default App
