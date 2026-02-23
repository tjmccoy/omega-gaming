'use client'

import { useEffect, useState } from 'react'
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

    const [timeRemaining, setTimeRemaining] = useState('')
  
  useEffect(() => {
    const countDownDate = new Date("Feb 23, 2026 15:00:00").getTime();

    const x = setInterval(function() {
      const now = new Date().getTime();
      const distance = countDownDate - now;

      const hours = Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
      const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
      const seconds = Math.floor((distance % (1000 * 60)) / 1000);

      setTimeRemaining(` ${hours}h ${minutes}m ${seconds}s`);
    }, 1000);

    return () => clearInterval(x);
  }, []);

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
          <div className='square'> Time Remaining <div>{timeRemaining}</div> 
          </div>
        </div>

        

      </div>
        </QueryClientProvider>
        </WagmiProvider>
  </>
  )
}

export default App
