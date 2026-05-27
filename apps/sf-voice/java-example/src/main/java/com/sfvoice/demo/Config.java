package sh.sf-voice.demo;

import com.sfvoice.media.SfVoiceMediaClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * wires the sf-voice SDK client as a Spring bean.
 * fails fast at startup if SF_VOICE_API_KEY is missing.
 */
@Configuration
public class Config {

    /**
     * Creates and configures an SfVoiceMediaClient bean from environment variables.
     *
     * <p>Reads the environment variable {@code SF_VOICE_API_KEY} and fails fast if it is missing or blank.
     * If {@code SF_VOICE_BASE_URL} is missing or blank, the client is configured to use {@code https://api.sf-voice.com}.</p>
     *
     * @return an SfVoiceMediaClient configured with the resolved API key and base URL
     * @throws IllegalStateException if {@code SF_VOICE_API_KEY} is missing or blank
     */
    @Bean
    public SfVoiceMediaClient sfVoiceClient() {
        String apiKey = System.getenv("SF_VOICE_API_KEY");
        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalStateException("required env var missing: SF_VOICE_API_KEY");
        }

        String baseUrl = System.getenv("SF_VOICE_BASE_URL");
        if (baseUrl == null || baseUrl.isBlank()) {
            baseUrl = "https://api.sf-voice.com";
        }

        return new SfVoiceMediaClient.Builder()
                .apiKey(apiKey)
                .baseUrl(baseUrl)
                .build();
    }
}
