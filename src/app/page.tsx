'use client'

import { useConnect, useConnection, useConnectors, useDisconnect } from 'wagmi'

function App() {
  const connection = useConnection()
  const { connect, status, error } = useConnect()
  const connectors = useConnectors()
  const { disconnect } = useDisconnect()

  return (
    <>
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

        <div className='squares-container'> 
          <div className='square'> Active Players </div>
          <div className='square'> Prize Pool </div>
          <div className='square'> Time Remaining </div>
        </div>

        

      </div>

      
    </>
  )
}

export default App
