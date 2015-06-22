-- | Server-side funtionality for creating index tarballs
{-# LANGUAGE BangPatterns #-}
module Hackage.Security.Server.IndexTarball (
    append
  ) where

import Control.Exception
import Control.Monad
import qualified Codec.Archive.Tar       as Tar
import qualified Codec.Archive.Tar.Index as Tar
import qualified Data.ByteString.Lazy    as BS.L

import Hackage.Security.Util.Path

-- | Append (or create) some files to tarball
append :: (IsFileSystemRoot root, IsFileSystemRoot root')
       => Path (Rooted root)  -- ^ Location of the tar-file
       -> Path (Rooted root') -- ^ Base directory of new files to be added
       -> [TarballPath]       -- ^ Files to be added
       -> IO ()
append tar baseDir newFiles =
    seekTarball tar $ \h -> do
      newEntries <- tarPack baseDir newFiles
      BS.L.hPut h $ Tar.write newEntries

-- | Open (or create) a tarball and seek it to the end so we can start
-- writing new entries.
seekTarball :: IsFileSystemRoot root
            => Path (Rooted root) -> (Handle -> IO a) -> IO a
seekTarball tar callback = do
    withFile tar ReadWriteMode $ \h -> do
      isEmpty <- (== 0) <$> hFileSize h
      unless isEmpty $ seekToEnd h
      callback h

-- | Seek a tarball to the end
seekToEnd :: Handle -> IO ()
seekToEnd h = go Tar.emptyIndex
  where
    go :: Tar.IndexBuilder -> IO ()
    go ib = do
      let nextOffset = Tar.nextEntryOffset ib
      mEntry <- hReadEntryHeader h nextOffset
      case mEntry of
        Nothing -> Tar.hSeekEntryOffset h nextOffset
        Just e  -> go (Tar.skipNextEntry e ib)

-- | Variation on `hReadEntryHeader` that returns `Nothing` if we have reached
-- the end of the tar file
--
-- TODO: This should move to the `tar` package.
hReadEntryHeader :: Handle -> Tar.TarEntryOffset -> IO (Maybe Tar.Entry)
hReadEntryHeader hnd blockOff = do
    Tar.hSeekEntryOffset hnd blockOff
    header <- BS.L.hGet hnd 1024
    case Tar.read header of
      Tar.Next entry _ -> return $ Just entry
      Tar.Done         -> return $ Nothing
      Tar.Fail e       -> throwIO e
