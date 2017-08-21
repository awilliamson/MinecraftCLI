{-# LANGUAGE RecordWildCards, OverloadedStrings #-}
module Main where

import           Control.Monad (void, replicateM_)
import           Control.Monad.IO.Class
import qualified Data.ByteString as BS
import           Data.Monoid
import qualified Data.Text as Text
import           GHC.IO.Handle
import           Network.Socket hiding (send, sendTo, recv, recvFrom)
import           System.IO (IOMode(..))

import Network.Protocol.Minecraft.Encoding
import Network.Protocol.Minecraft.Packet
import Network.Protocol.Minecraft.Types
import Network.Protocol.Minecraft.Yggdrasil

main :: IO ()
main = do
    let uuid = "Your UUID"
        token = "Your auth token"
    sock <- socket AF_INET Stream defaultProtocol
    --connect sock (SockAddrInet 25565 (tupleToHostAddress (7, 4, 219, 104)))
    connect sock (SockAddrInet 25565 (tupleToHostAddress (104, 219, 4, 7)))

    putStrLn "Connected"

    handle <- socketToHandle sock ReadWriteMode
    --hSetBuffering handle (BlockBuffering Nothing)

    putStrLn "Got handle"

    void $ runEncodedT (defaultEncodingState handle) $ do
        let handshake = PacketHandshakePayload 335 "102.219.4.7" 25565 LoggingIn
        sendPacket handshake

        liftIO $ putStrLn "Handshake sent"

        let loginStart = PacketLoginStartPayload "Yotanido"
        sendPacket loginStart

        liftIO $ putStrLn "LoginStart sent"

        PacketEncryptionRequest encRequest <- readPacket LoggingIn

        liftIO $ putStrLn "Response received"

        liftIO $ putStrLn "decoded pubkey"

        sharedSecret <- liftIO $ generateSharedKey

        liftIO $ putStrLn "Generating shared secret"

        let serverHash = createServerHash (unNetworkText $ serverID encRequest) sharedSecret (pubKey encRequest)
            joinRequest = JoinRequest token uuid (Text.pack serverHash)

        joinSucc <- liftIO $ join joinRequest
        liftIO $ putStrLn $ if joinSucc then "Join successful" else "Join failed"

        Just response <- liftIO $ encryptionResponse sharedSecret encRequest
        sendPacket response

        liftIO $ putStrLn "Encryption response sent"

        True <- enableEncryption sharedSecret
        pure ()

        replicateM_ 2 $ do
            packet <- readPacket LoggingIn

            case packet of
              PacketSetCompression (PacketSetCompressionPayload thresh) -> setCompressionThreshold (fromIntegral thresh)
              PacketLoginSuccess PacketLoginSuccessPayload{..} -> liftIO . putStrLn . Text.unpack $ "Login success! " <> unNetworkText successUsername <> " " <> unNetworkText uuid
              PacketUnknown (PacketUnknownPayload bs) -> liftIO . putStrLn . show . BS.unpack $ bs
              ConnectionClosed -> liftIO $ putStrLn "Connection closed"
              _ -> pure ()

    hClose handle
    pure ()
