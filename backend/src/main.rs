mod lxmusic;
mod lyrics;
mod model;
mod mpris;
mod server;

use anyhow::Result;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let registry = mpris::PlayerRegistry::start().await?;
    let lyrics = lyrics::LyricsManager::new()?;
    let lxmusic = lxmusic::LxMusicManager::new()?;
    server::serve(registry, lyrics, lxmusic).await
}
