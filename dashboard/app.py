import streamlit as st
import pandas as pd
import pathlib

st.set_page_config(layout='wide', page_title='Engineer Impact — Prototype')

metrics_path = pathlib.Path(__file__).resolve().parents[1] / 'metrics.csv'
if not metrics_path.exists():
    st.error('metrics.csv not found. Run scripts/parse_git.py and scripts/aggregate_metrics.py first.')
    st.stop()

df = pd.read_csv(metrics_path)
df = df.sort_values('impact_score', ascending=False).reset_index(drop=True)
df.index += 1
top5 = df.head(5)

st.title('Most Impactful Engineers')

with st.expander('How is impact scored?'):
    st.markdown("""
**Impact score** = `downstream_mods_90d × log(1 + functions_introduced) + median_survivability / 90`

| Component | What it measures |
|---|---|
| `downstream_mods_90d` | Distinct commits by *other* engineers that touched functions this person introduced, within 90 days — a proxy for how foundational their code is |
| `log(1 + functions_introduced)` | Breadth of authorship (log-scaled to avoid penalising focused contributors) |
| `median_survivability / 90` | How long introduced functions survive unmodified — higher means more stable, correct-first-time code |

A high score means: wrote code that others built on quickly, across many functions, and that needed little rework.
""")

st.subheader('Top 5')
cols = st.columns(5)
for i, (_, row) in enumerate(top5.iterrows()):
    cols[i].metric(
        label=row['creator'],
        value=f"{row['impact_score']:.1f}",
        delta=f"{int(row['total_future_mods_90d'])} downstream mods"
    )

st.subheader('Why these engineers?')
for _, r in top5.iterrows():
    st.markdown(
        f"**{r['creator']}** — introduced {int(r['introduced_functions'])} functions "
        f"that attracted {int(r['total_future_mods_90d'])} downstream commits within 90 days; "
        f"median survivability {int(r['median_survivability'])} days."
    )

st.divider()
st.subheader('Full ranking')
st.dataframe(
    df.rename(columns={
        'creator': 'Engineer',
        'introduced_functions': 'Functions introduced',
        'total_future_mods_90d': 'Downstream mods (90d)',
        'median_survivability': 'Median survivability (days)',
        'impact_score': 'Impact score',
    }),
    use_container_width=True,
)
