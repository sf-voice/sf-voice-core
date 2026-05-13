-- demo seed for the sf-voice debugging product.
-- idempotent — re-running wipes the demo org's data and reinserts.
-- run with: docker exec -i sf-voice-mysql mysql -u sf_voice -psf_voice sf_voice_dev < infra/dev/seed-demo.sql
--
-- ids are stable so the frontend can hardcode them during dev:
--   org   = 01900000-0000-7000-8000-000000000001
--   call  = 01900000-0000-7000-8000-000000000010
--   run   = 01900000-0000-7000-8000-000000000020
--
-- audio_uri points at a static file the frontend serves from its public/
-- folder. drop a sample at core/frontend/public/sample-call.mp3.

START TRANSACTION;

-- wipe demo first. order respects fk constraints.
DELETE FROM transcripts        WHERE call_id   = UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-',''));
DELETE FROM transcript_runs    WHERE call_id   = UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-',''));
DELETE FROM prompt_slices      WHERE org_id    = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''));
DELETE FROM jobs               WHERE org_id    = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''));
DELETE FROM files              WHERE org_id    = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''));
DELETE FROM calls              WHERE org_id    = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''));
DELETE FROM orgs               WHERE id        = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''));

INSERT INTO orgs (id, name, slug, slack_webhook_url)
VALUES (
  UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-','')),
  'Demo Restaurant',
  'demo',
  NULL
);

-- a 48-second call. the transcripts below add up to 47.8s. one engineered
-- interrupt at 0:14.2 (ai starts during caller turn 3).
INSERT INTO calls (id, org_id, started_at, ended_at, duration_ms,
                   caller_number, destination_number, termination_reason,
                   audio_uri, caller_audio_uri, ai_audio_uri)
VALUES (
  UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')),
  UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-','')),
  TIMESTAMPADD(MINUTE, -47, CURRENT_TIMESTAMP),
  TIMESTAMPADD(SECOND, -47*60 + 48, CURRENT_TIMESTAMP),
  48000,
  '+14155551234',
  '+18774980043',
  'caller_hangup',
  '/sample-call.mp3',
  '/sample-call.mp3',
  '/sample-call.mp3'
);

INSERT INTO transcript_runs (id, call_id, status,
                             whisper_model, diarization_model, vad_model,
                             triggered_by, started_at, finished_at)
VALUES (
  UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')),
  UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')),
  'done',
  'whisper-large-v3',
  'pyannote-3.1',
  'silero-vad-4',
  'seed',
  TIMESTAMPADD(MINUTE, -47, CURRENT_TIMESTAMP),
  TIMESTAMPADD(MINUTE, -46, CURRENT_TIMESTAMP)
);

-- per-utterance rows. each (start_ms, end_ms, speaker_label, text).
-- one interrupt: at row 6 the ai starts at 14_200 ms while the caller's
-- turn ends at 14_900 ms. that 700ms overlap is the engineered defect
-- the timeline highlights and the eval harness can be pointed at.
INSERT INTO transcripts (call_id, run_id, speaker_label, start_ms, end_ms, text, confidence, model_version) VALUES
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',      0,     1900,  'thanks for calling demo restaurant, this is ellie. how can i help?', 0.97, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller',  2100,  4800,  'hi yeah, i wanted to book a table for friday night', 0.92, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',      5100,  7600,  'absolutely. how many people will be joining you?', 0.96, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller',  7900, 10200,  'six adults and two kids', 0.95, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller', 11800, 14900,  'and is there any chance you have a window table available', 0.88, 'whisper-large-v3+pyannote-3.1'),
  -- engineered interrupt: ai starts at 14200, caller still going until 14900.
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     14200, 17500,  'we can do friday at seven. would that work?', 0.84, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller', 17800, 19600,  'um, seven thirty would be better actually', 0.91, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     20000, 22800,  'seven thirty on friday for eight people, let me check that.', 0.94, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     23200, 27100,  'okay, i have a table for eight at seven thirty on friday. can i grab your name?', 0.93, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller', 27500, 29400,  'yeah it''s under jordan', 0.96, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     29700, 32900,  'great. jordan, party of eight, friday seven thirty. anything else?', 0.95, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller', 33200, 35800,  'do you guys have anything for a peanut allergy?', 0.90, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     36100, 41200,  'yes, the kitchen handles allergies, i''ll add a note. anything else i can help with?', 0.92, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'caller', 41500, 43200,  'nope that''s all, thanks', 0.96, 'whisper-large-v3+pyannote-3.1'),
  (UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-','')), UNHEX(REPLACE('01900000-0000-7000-8000-000000000020','-','')), 'ai',     43500, 47800,  'you''re welcome, see you friday. bye.', 0.97, 'whisper-large-v3+pyannote-3.1');

COMMIT;

SELECT
  (SELECT COUNT(*) FROM orgs            WHERE id      = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''))) AS orgs,
  (SELECT COUNT(*) FROM calls           WHERE org_id  = UNHEX(REPLACE('01900000-0000-7000-8000-000000000001','-',''))) AS calls,
  (SELECT COUNT(*) FROM transcript_runs WHERE call_id = UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-',''))) AS runs,
  (SELECT COUNT(*) FROM transcripts     WHERE call_id = UNHEX(REPLACE('01900000-0000-7000-8000-000000000010','-',''))) AS transcripts;
