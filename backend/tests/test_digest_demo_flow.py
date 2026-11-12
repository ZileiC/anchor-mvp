"""Exercise the actual HTTP flow without a scheduler or fabricated production data."""
from datetime import datetime, timezone
from tests.helpers import headers, seed_consents, seed_adequate_observations, token_for


def test_generate_publish_read_revoke(client, app, senior, caregiver, senior_token, caregiver_token, linked):
    seed_consents(app, senior, record_observations=True, share_topics=('mood',))
    seed_adequate_observations(app, senior, topic='mood')
    sh, ch = headers(senior_token), headers(caregiver_token)
    generated = client.post('/api/v1/digests/generate', headers=sh)
    assert generated.status_code == 200, generated.text
    draft = generated.json()
    assert draft['status'] == 'draft'
    assert draft['period_start'] == '2025-12-29'
    assert draft['period_end'] == '2026-01-05'
    assert client.post('/api/v1/digests/generate', headers=sh).json()['id'] == draft['id']
    assert client.get('/api/v1/digests', headers=ch).json()['items'] == []
    published = client.post(f"/api/v1/digests/{draft['id']}/publish", headers=sh)
    assert published.status_code == 200, published.text
    assert published.json()['status'] == 'delivered'
    assert client.post(f"/api/v1/digests/{draft['id']}/publish", headers=sh).status_code == 200
    inbox = client.get('/api/v1/notifications', headers=ch).json()['items']
    assert len(inbox) == 1
    assert inbox[0]['read_at'] is None
    assert client.patch(f"/api/v1/notifications/{inbox[0]['id']}", headers=ch).json()['read_at']
    assert client.get('/api/v1/digests', headers=ch).json()['items'][0]['items']
    consent = client.get('/api/v1/consents', headers=sh).json()
    response = client.put('/api/v1/consents', headers=sh, json={
        'base_version': consent['version'],
        'changes': [{'capability': 'share_topic', 'topic': 'mood', 'allowed': False}],
    })
    assert response.status_code == 200, response.text
    assert not client.get('/api/v1/digests', headers=ch).json()['items'][0]['items']


def test_generate_sparse_data_and_access_checks(client, app, senior, caregiver_token, senior_token, make_user):
    sh, ch = headers(senior_token), headers(caregiver_token)
    assert client.post('/api/v1/digests/generate').status_code == 401
    assert client.post('/api/v1/digests/generate', headers=ch).status_code == 403
    draft = client.post('/api/v1/digests/generate', headers=sh).json()
    assert draft['status'] == 'insufficient_data'
    assert client.post(f"/api/v1/digests/{draft['id']}/publish", headers=sh).status_code == 409
    assert client.post(f"/api/v1/digests/{draft['id']}/publish", headers=ch).status_code == 403
    other = make_user('senior', 'Other')
    assert client.post(f"/api/v1/digests/{draft['id']}/publish", headers=headers(token_for(app, other))).status_code == 404


def test_generation_uses_senior_local_week(client, app, senior, senior_token, clock):
    # UTC is still Sunday, but Shanghai has reached Monday.
    clock.set(datetime(2026, 1, 4, 17, 0, tzinfo=timezone.utc))
    draft = client.post('/api/v1/digests/generate', headers=headers(senior_token)).json()
    assert draft['period_start'] == '2025-12-29'
    assert draft['period_end'] == '2026-01-05'


def test_revoked_topic_cannot_be_published(client, app, senior, senior_token, linked):
    seed_consents(app, senior, record_observations=True, share_topics=('mood',))
    seed_adequate_observations(app, senior, topic='mood')
    sh = headers(senior_token)
    draft = client.post('/api/v1/digests/generate', headers=sh).json()
    version = client.get('/api/v1/consents', headers=sh).json()['version']
    client.put('/api/v1/consents', headers=sh, json={'base_version': version,
        'changes': [{'capability': 'share_topic', 'topic': 'mood', 'allowed': False}]})
    assert client.post(f"/api/v1/digests/{draft['id']}/publish", headers=sh).status_code == 409
    assert app.state.db.scalar('SELECT COUNT(*) FROM notifications') == 0
